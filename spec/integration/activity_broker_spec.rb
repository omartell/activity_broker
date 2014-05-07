require 'spec_helper'
require 'socket'

module AsyncHelper
  def eventually(options = {})
    timeout = options[:timeout]   || 5
    interval = options[:interval] || 0.0001
    time_limit = Time.now + timeout
    loop do
      begin
        yield
      rescue => error
      end
      return if error.nil?
      if Time.now >= time_limit
        raise error
      end
      sleep interval
    end
  end
end

describe 'Activity Broker' do
  include AsyncHelper
  CRLF = '/r/n'

  class FakeEventSource
    def initialize(host, port)
      @host = host
      @port = port
    end

    def start
      @connection = Socket.tcp(@host, @port)
    end

    def send_broadcast_event
      send_event('1|B')
    end

    def send_follow_event
      send_event('4327421|F|118|974')
    end

    def send_event(message)
      puts 'sending event' + message
      @connection.write(message)
      @connection.write(CRLF)
    end

    def stop
      @connection.close
    end
  end

  class Queue
    def self.create_with_pipes
      readable_pipe_sender, writable_pipe_sender = IO.pipe
      new(readable_pipe_sender, writable_pipe_sender)
    end

    def self.create_with_unix_sockets
      child_socket, parent_socket = Socket.pair(:UNIX, :DGRAM, 0)
      new(child_socket, parent_socket)
    end

    def initialize(to_read, to_write)
      @to_read  = to_read
      @to_write = to_write
    end

    def pop
      if ready = IO.select([@to_read], nil, nil, 0)
        pop!
      end
    end

    def pop!
      if message = @to_read.gets(CRLF)
        message.gsub(CRLF, "")
      end
    end

    def push(message)
      @to_write.write(message)
      unless message.scan(CRLF)
        @to_write.write(CRLF)
      end
    end
  end

  class ApplicationRunner
    def initialize(config)
      @config = config
    end

    def start
      trap(:INT) do
        @event_source_server.stop
        @subscriber_server.stop
        exit
      end

      loop do
        event_loop = EventLoop.new
        event_forwarder = EventForwarder.new

        @event_source_server = Server.new(@config[:event_source_exchange_port], event_loop)
        @subscriber_server = Server.new(@config[:subscriber_exchange_port], event_loop)

        @event_source_server.accept_connections do |message_stream|
          message_stream.start_reading(MessageTranslator.new(event_forwarder))
        end

        @subscriber_server.accept_connections do |message_stream|
          message_stream.start_reading(MessageTranslator.new(event_forwarder))
        end

        event_loop.start
      end
    end
  end

  class Server
    def initialize(port, io_loop)
      @connections = []
      @port = port
      @io_loop = io_loop
    end

    def accept_connections(&connection_listener)
      @server = TCPServer.new(@port)
      @connection_listener = connection_listener
      @io_loop.register_read(self, :new_connection_ready)
    end

    def to_io
      @server
    end

    def stop
      @server.close
    end

    def new_connection_ready
      connection = @server.accept_nonblock
      @connection_listener.call(MessageStream.new(connection, @io_loop))
    end

    private

    def add_connection(c)
      @connections << c
    end
  end

  class EventForwarder
    def initialize
      @subscribers = {}
    end

    def new_subscriber(client_id, message, connection)
      puts 'client_id_received ' + client_id
      @subscribers[client_id] = connection
    end

    def broadcast_event_received(event_id, message, connection)
      puts 'received broadcast ' + event_id.to_s + @subscribers.size.to_s
      @subscribers.each do |client_id, connection|
        connection.deliver(message)
      end
    end
  end

  class SubscriberPool
    def initialize
      @pool = {}
    end
    def add_subscriber(id, connection)
      @pool[id] = connection
    end
  end

  class MessageTranslator
    def initialize(listener)
      @listener = listener
    end

    def new_message(message, stream)
      if message == '1|B'
        @listener.broadcast_event_received(message, message, stream)
      else
        @listener.new_subscriber(message, message, stream)
      end
    end
  end

  class MessageStream
    def initialize(io, io_loop)
      @io = io
      @io_loop = io_loop
      @read_buffer = ""
    end

    def start_reading(message_listener)
      @message_listener = message_listener
      @io_loop.register_read(self, :data_received)
    end

    def to_io
      @io
    end

    def data_received
      begin
        @read_buffer << @io.read_nonblock(4096)
        forward_messages
      rescue IO::WaitReadable
        # Oops, turned out the IO wasn't actually readable.
      rescue EOFError, Errno::ECONNRESET
        # Connection closed
      end
    end

    def regex
      /([ A-Z | \d | a-z | \|]*)\/r\/n/
    end

    def deliver(message)
      puts 'delivering' + message
      @io.write(message)
      @io.write(CRLF)
    end

    def forward_messages
      @read_buffer.scan(regex).flatten.each do |m|
        @message_listener.new_message(m, self)
      end
      @read_buffer.gsub!(regex)
    end
  end

  class EventLoop
    def initialize
      @reading = []
      @writing = []
    end

    def start
      loop do
        ready_reading, ready_writing, _ = IO.select(@reading, @writing, nil, 0)
        ((ready_writing || []) + (ready_reading || [])).each(&:notify)
      end
    end

    def register_read(listener, event = nil, &block)
      @reading << IOListener.new(listener, event, block)
    end

    def register_write(listener, event = nil, &block)
      @writing << IOListener.new(listener, event, block)
    end
  end

  class IOListener
    def initialize(listener, event, block)
      @listener = listener
      @event = event
      @block = block
    end

    def to_io
      @listener.to_io
    end

    def notify
      if @event
        @listener.send(@event)
      else
        @block.call(@listener)
      end
    end
  end

  class MessageReader
    def initialize(io)
      @io = io
    end

    def each(&block)
      read_loop(1, &block)
    end

    def read_loop(timeout_seconds = 0, &on_message_received)
      loop do
        if ready = IO.select([@io], nil, nil, timeout_seconds)
          message = next_message
          unless message.nil?
            on_message_received.call(message)
          end
        end
      end
    end

    def read!(timeout_seconds = 0)
      if ready = IO.select([@io], nil, nil, timeout_seconds)
        next_message
      end
    end

    private

    def next_message
      @io.to_io.gets(CRLF)
    end
  end

  class Logger
    def initialize(id)
      @id = id
    end

    def notify(event, *other)
      send(event, *other)
    end

    private

    def monitoring_connections(port)
      log('started tcp server on ' + port.to_s)
    end

    def new_client_connection_accepted(connection)
      log('new client connection accepted')
    end

    def message_received(message)
      log('message received' + message)
    end

    def message_sent(message)
      log('message sent' + message)
    end

    def exchange_exit
      log('exchange stopped')
    end

    def log(message)
      puts @id + ' | ' + message
    end
  end

  class FakeSubscriber
    def initialize(client_id, address, port)
      @client_id = client_id
      @address = address
      @port = port
      @events = []
    end

    def start
      begin
        @connection = Socket.tcp(@address, @port)
      rescue Errno::ECONNREFUSED
        retry
      end
    end

    def monitor
      Thread.new do
        loop do
          message = @connection.gets(CRLF)
          @events << message.gsub!(CRLF)
        end
      end
    end

    def send_client_id
      @connection.write(@client_id)
      @connection.write(CRLF)
      puts 'sending client id ' + @client_id
    end

    def received_broadcast_event?
      received_event?('1|B')
    end

    def received_follow_event?
      received_event?('4327421|F|118|974')
    end

    def received_event?(event)
      return @has_received_event if @has_received_event

      if @events.size > 0
        puts @client_id + ' got event: ' + event
        @has_received_event = true
        event == @events.last
      else
        read_ready, _, _ = IO.select([@connection], nil, nil, 0)
        if read_ready
          @events << read_ready.first.gets(CRLF)
        end
      end
    end

    def stop
      @connection.close
    end
  end

  it 'A subscriber is notified of broadcast event' do
    @runner = ApplicationRunner.new({ event_source_exchange_port: 4484,
                                      subscriber_exchange_port: 4485 })
    @runnerpid = fork do
      @runner.start
    end

    bob = start_subscriber('bob', 4485)

    @source = FakeEventSource.new('localhost', 4484)
    @source.start
    @source.send_broadcast_event

    eventually do
      expect(bob.received_broadcast_event?).to eq true
    end
  end

  specify 'A couple of subscribers are notified of broadcast event' do
    @runner = ApplicationRunner.new({ event_source_exchange_port: 4484,
                                      subscriber_exchange_port: 4485 })
    @runnerpid = fork do
      @runner.start
    end

    subscribers = 10.times.map do |id|
      start_subscriber('alice' + id.to_s, 4485)
    end

    @source = FakeEventSource.new('localhost', 4484)
    @source.start
    @source.send_broadcast_event

    eventually do
      expect(subscribers.all?(&:received_broadcast_event?)).to eq true
    end
  end

  def start_subscriber(id, port)
    FakeSubscriber.new(id, 'localhost', port).tap do |s|
      s.start
      s.send_client_id
      @subscribers.push(s)
    end
  end

  before do
    @subscribers = []
  end

  after do
    @source.stop
    @subscribers.each(&:stop)
    Process.kill(:INT, @runnerpid) if @runnerpid
  end
end

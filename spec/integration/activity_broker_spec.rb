require 'spec_helper'
require 'support/async_helper'
require 'socket'

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

    def publish_broadcast_event
      publish_event('1|B')
    end

    def publish_new_follower_to(followed, follower)
      publish_event('4327421|F|' + follower + '|' + followed)
    end

    def publish_status_update_from(from)
      publish_event(event_id + '|S|' + from)
    end

    def publish_private_message_to(to, from)
      publish_event('4327425|P|' + from + '|' + to)
    end

    def publish_unfollow_to(unfollowed, unfollower)
      publish_event('4327361|U|' + unfollower + '|' + unfollowed)
    end

    def publish_event(message)
      puts 'publishing event' + message
      @connection.write(message)
      @connection.write(CRLF)
      message
    end

    def event_id
      Random.rand(10000..20000).to_s
    end

    def stop
      @connection.close
    end
  end

  class ApplicationRunner
    def initialize(config)
      @config = config
      @event_loop = EventLoop.new
    end

    def listen
      @event_source_server = Server.new(@config[:event_source_exchange_port], @event_loop)
      @subscriber_server   = Server.new(@config[:subscriber_exchange_port], @event_loop)
    end

    def start
      event_forwarder = EventForwarder.new(@config.fetch(:logger){ Logger.new })

      @event_source_server.accept_connections do |message_stream|
        message_stream.start_reading(MessageTranslator.new(event_forwarder))
      end

      @subscriber_server.accept_connections do |message_stream|
        message_stream.start_reading(MessageTranslator.new(event_forwarder))
      end

      trap_signal
      @event_loop.start
    end

    def trap_signal
      trap(:INT) do
        @event_source_server.stop
        @subscriber_server.stop
        exit
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
      puts 'start accepting connections in server'
      @server = TCPServer.new(@port)
      @connection_listener = connection_listener
      @io_loop.register_read(self, :process_new_connection)
    end

    def to_io
      @server
    end

    def stop
      @server.close
    end

    def process_new_connection
      connection = @server.accept_nonblock
      add_connection(connection)
      puts 'connection accepted on server ' + @connections.size.to_s
      @connection_listener.call(MessageStream.new(connection, @io_loop))
    end

    def add_connection(c)
      @connections << c
    end
  end

  class EventForwarder
    def initialize(logger)
      @subscribers = {}
      @followers   = {}
      @logger      = logger
    end

    def add_subscriber(client_id, message, subscriber_stream)
      puts ' client_id_received ' + client_id
      @subscribers[client_id] = subscriber_stream
      subscriber_stream.deliver('welcome')
    end

    def process_broadcast_event(event_id, message, source_event_stream)
      puts 'forwarding broadcast ' + event_id.to_s + @subscribers.size.to_s
      @subscribers.each do |client_id, subscriber_stream|
        subscriber_stream.deliver(message)
      end
    end

    def process_follow_event(followed, follower, message, source_event_stream)
      puts 'forwarding follow event to ' + followed
      @followers[followed] ||= []
      @followers[followed] << follower
      @subscribers[followed].deliver(message)
    end

    def process_unfollow_event(followed, follower, message, source_event_stream)
      puts 'forwarding unfollow event to ' + followed
      @subscribers[followed].deliver(message)
    end

    def process_status_update_event(from, message)
      @followers[from].each do |subscriber_id|
        @subscribers.fetch(subscriber_id).deliver(message)
      end
    end

    def process_private_message_event(to, from, message, source_event_stream)
      @subscribers.fetch(to).deliver(message)
    end
  end

  class MessageTranslator
    def initialize(listener)
      @listener = listener
    end

    def process_message(message, source_event_stream)
      id, event, from, to = message.split('|')

      if event == 'B'
        @listener.process_broadcast_event(message, message, source_event_stream)
      elsif event == 'F'
        @listener.process_follow_event(to, from, message, source_event_stream)
      elsif event == 'U'
        @listener.process_unfollow_event(to, from, message, source_event_stream)
      elsif event == 'P'
        @listener.process_private_message_event(to, from, message, source_event_stream)
      elsif event == 'S'
        @listener.process_status_update_event(from, message)
      else
        @listener.add_subscriber(message, message, source_event_stream)
      end
    end
  end

  class MessageStream
    def initialize(io, io_loop)
      @io = io
      @io_loop = io_loop
      @read_buffer = ''
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
        read = @io.read_nonblock(4096)
        @read_buffer << read
        forward_messages
      rescue IO::WaitReadable
        # Oops, turned out the IO wasn't actually readable.
      rescue EOFError, Errno::ECONNRESET
        # Connection closed
      end
    end

    def deliver(message)
      puts 'delivering ' + message
      @io.write(message)
      @io.write(CRLF)
    end

    def forward_messages
      @read_buffer.scan(message_regex).flatten.each do |m|
        puts 'processing message ' + m
        @message_listener.process_message(m, self)
      end
      @read_buffer = @read_buffer.gsub(message_regex, "")
    end

    private

    def message_regex
      /([^\/]*)\/r\/n/
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

  class Logger
    def initialize

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
      puts Time.now.to_s + ' | ' + message
    end
  end

  class FakeSubscriber
    def initialize(client_id, address, port)
      @client_id = client_id
      @address   = address
      @port      = port
      @events    = []
    end

    def start
      begin
        @connection = Socket.tcp(@address, @port)
      rescue Errno::ECONNREFUSED
        retry
      end
    end

    def send_client_id
      @connection.write(@client_id)
      @connection.write(CRLF)
      puts 'writing client id ' + @client_id
    end

    def received_broadcast_event?
      received_message?('1|B')
    end

    def received_follow_event?(follower)
      received_message?('4327421|F|' + follower + '|' + @client_id)
    end

    def received_status_update?(from)
      received_message?('4327368|S|' + from)
    end

    def received_unfollow_event?(unfollower)
      received_message?('4327361|U|' + unfollower + '|' + @client_id)
    end

    def received_private_message?(from)
      received_message?('4327425|P|' + from + '|' + @client_id)
    end

    def received_joined_ack?
      received_message?('welcome')
    end

    def received_message?(expected_event)
      return true if @events.include?(expected_event)

      read_ready, _, _ = IO.select([@connection], nil, nil, 0)
      if read_ready
        buffer = read_ready.first.read_nonblock(4096)
        buffer.split(CRLF).each do |e|
          puts @client_id + ' got event: ' + e
          @events << e
        end
      end
    end

    def stop
      @connection.close
    end
  end

  let!(:broker) do
    ApplicationRunner.new({ event_source_exchange_port: 4484,
                            subscriber_exchange_port: 4485,
                            logger: Logger.new }).tap do |a|
      a.listen
    end
  end

  let!(:source) do
    FakeEventSource.new('0.0.0.0', 4484)
  end

  def start_activity_broker
    @brokerpid = fork { broker.start }
  end

  specify 'A subscriber is notified of broadcast event' do
    start_activity_broker

    bob = start_subscriber('bob', 4485)

    source.start
    source.publish_broadcast_event

    eventually do
      expect(bob.received_broadcast_event?).to eq true
    end
  end

  specify 'A couple of subscribers are notified of broadcast event' do
    start_activity_broker

    subscribers = 10.times.map do |id|
      start_subscriber('alice' + id.to_s, 4485)
    end

    source.start
    source.publish_broadcast_event

    eventually do
      subscribers.each do |s|
        expect(s.received_broadcast_event?).to eq true
      end
    end
  end

  specify 'Subscriber receives followed event after event source sends follow notification' do
    start_activity_broker

    bob   = start_subscriber('bob', 4485)
    alice = start_subscriber('alice', 4485)

    source.start
    source.publish_new_follower_to('bob', 'alice')

    eventually do
      expect(bob.received_follow_event?('alice')).to eq true
    end
  end

  specify 'Multiple followed events notifications are sent to followed subscribers' do
    start_activity_broker

    bob     = start_subscriber('bob', 4485)
    alice   = start_subscriber('alice', 4485)
    robert  = start_subscriber('robert', 4485)

    source.start

    source.publish_new_follower_to('bob', 'alice')
    source.publish_new_follower_to('bob', 'robert')

    source.publish_new_follower_to('alice', 'robert')
    source.publish_new_follower_to('alice', 'bob')

    source.publish_new_follower_to('robert', 'alice')
    source.publish_new_follower_to('robert', 'bob')

    eventually do
      expect(bob.received_follow_event?('alice')).to eq true
      expect(bob.received_follow_event?('robert')).to eq true

      expect(alice.received_follow_event?('bob')).to eq true
      expect(alice.received_follow_event?('robert')).to eq true

      expect(robert.received_follow_event?('bob')).to eq true
      expect(robert.received_follow_event?('alice')).to eq true
    end
  end

  specify 'Unfollowed notification is forwarded to subscriber' do
    start_activity_broker

    bob   = start_subscriber('bob', 4485)
    alice = start_subscriber('alice', 4485)

    source.start

    source.publish_new_follower_to('bob', 'alice')
    source.publish_unfollow_to('bob', 'alice')

    eventually do
      expect(bob.received_unfollow_event?('alice')).to eq true
    end
  end

  specify 'Subscriber is notified of private message' do
    start_activity_broker

    bob   = start_subscriber('bob', 4485)
    alice = start_subscriber('alice', 4485)

    source.start

    source.publish_private_message_to('bob', 'alice')

    eventually do
      expect(bob.received_private_message?('alice')).to eq true
    end
  end

  specify 'Followers are notified of status update from other user' do
    start_activity_broker

    bob   = start_subscriber('bob', 4485)
    alice = start_subscriber('alice', 4485)

    source.start

    source.publish_new_follower_to('bob', 'alice')
    source.publish_status_update_from('bob')
    source.publish_new_follower_to('alice', 'bob')
    source.publish_status_update_from('alice')

    eventually do
      expect(alice.received_status_update?('bob')).to eq true
      expect(bob.received_status_update?('alice')).to eq true
    end
  end

  def start_subscriber(id, port)
    FakeSubscriber.new(id, '0.0.0.0', port).tap do |s|
      s.start
      s.send_client_id
      eventually { expect(s.received_joined_ack?).to eq true }
      @subscribers.push(s)
    end
  end

  before do
    @subscribers = []
  end

  after do
    source.stop
    @subscribers.each(&:stop)
    Process.kill(:INT, @brokerpid) if @brokerpid
  end
end

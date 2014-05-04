require 'spec_helper'
require 'socket'

module AsyncHelper
  def eventually(options = {})
    timeout = options[:timeout]   || 5
    interval = options[:interval] || 0.1
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
      @connection.write('1|B')
      @connection.write(CRLF)
      puts 'sending event'
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

    def pop!
      if message = @to_read.gets(CRLF)
        message.gsub(CRLF, "")
      end
    end

    def to_io
      @to_read
    end

    def push(message)
      @to_write.write(message)
      @to_write.write(CRLF)
    end
  end

  class ApplicationRunner
    def initialize(config)
      @config = config
    end

    def start
      delivery_queue     = Queue.create_with_unix_sockets
      subscribers_queue  = Queue.create_with_unix_sockets
      event_source_exchange = Exchange.new(@config[:event_source_exchange_port],
                                           logger: Logger.new('event_source'))
      delivery_exchange  = Exchange.new(@config[:subscriber_exchange_port],
                                        logger: Logger.new('delivery exchange'))

      @babysitting = []

      @babysitting << fork do
        trap_signal(:INT)
        event_source_exchange.monitor do |client_connection|
          @babysitting << fork do
             trap(:INT){ exit }
            client_connection.receive_messages{ |message| delivery_queue.push(message) }
          end
        end
        client_connection.close
      end

      @babysitting << fork do
        trap_signal(:INT)
        delivery_exchange.monitor do |client_connection|
          @babysitting << fork do
            trap(:INT){ exit }
            client_connection.receive_messages{ |message| subscribers_queue.push(message) }
          end
          @babysitting << fork do
            trap(:INT){ exit }
            loop do
              message = delivery_queue.pop!
              client_connection.deliver_message(message)
            end
          end
          client_connection.close
        end
      end

      trap_signal(:INT)

      Process.waitall
    end

    def trap_signal(signal)
      trap(signal) do
        @babysitting.each do |cpid|
          puts 'stopping process' + cpid.to_s
          Process.kill(:INT, cpid)
        end
        exit
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

    def read_loop(timeout_seconds = 1, &on_message_received)
      loop do
        if ready = IO.select([@io], nil, nil, timeout_seconds)
          message = next_message
          unless message.nil?
            on_message_received.call(message)
          end
        end
      end
    end

    def read!(timeout_seconds = 1)
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
      puts @id + '|' + message
    end
  end

  class ClientConnection
    def initialize(connection, logger)
      @connection = connection
      @logger = logger
    end

    def receive_messages(&message_received)
      MessageReader.new(@connection).each do |message|
        @logger.notify(:message_received, message)
        message_received.call(message)
      end
    end

    def deliver_message(message)
      @connection.write(message)
      @connection.write(CRLF)
      @logger.notify(:message_sent, message)
    end

    def close
      @connection.close
    end
  end

  class MessageRouter
    def receive_message

    end

    def deliver_message

    end
  end

  class Exchange
    attr_accessor :children

    def initialize(port, dependencies = {})
      @port = port
      @babysitting = []
      @incoming_queue = dependencies[:incoming_queue]
      @outgoing_queue = dependencies[:outgoing_queue]
      @logger = dependencies[:logger]
    end

    def monitor(&connection_received)
      server = TCPServer.new(@port)
      @logger.notify(:monitoring_connections, @port)

      Socket.accept_loop(server) do |connection|
        @logger.notify(:new_client_connection_accepted, connection)
        connection_received.call(ClientConnection.new(connection, Logger.new('client_connection')))
      end
    end
  end

  class FakeSubscriber
    def initialize(client_id, address, port)
      @client_id = client_id
      @address = address
      @port = port
      @babysitting = []
      @events = []
    end

    def start
      begin
        @connection = Socket.tcp(@address, @port)
      rescue Errno::ECONNREFUSED
        retry
      end
      @readable_pipe, @writable_pipe = IO.pipe
      id = fork do
        trap(:INT){ exit }
        MessageReader.new(@connection).read_loop do |message|
          @writable_pipe.write(message)
        end
      end
      @babysitting << id
      Process.detach(id)
    end

    def send_id
      @connection.write(@client_id)
      @connection.write(CRLF)
      puts 'writing something'
    end

    def received_broadcast_event?
      if message = MessageReader.new(@readable_pipe).read!.gsub(CRLF, '')
        puts 'reading event from broker' + message
        message == '1|B'
      end
    end

    def stop
      @connection.close
      @babysitting.each do |pid|
        Process.kill(:INT, pid)
      end
    end
  end

  specify 'A subscriber is notified of broadcast event' do
    #start activity broker?
    #event source connects
    #client source connects
    #source sends broadcast vent
    #broker receives event
    #client receives event
    @runner = ApplicationRunner.new({ event_source_exchange_port: 4484,
                                      subscriber_exchange_port: 4485 })
    @runnerpid = fork do
      @runner.start
    end

    @subscriber = FakeSubscriber.new('bob', 'localhost', 4485)
    @subscriber.start
    @subscriber.send_id

    @source = FakeEventSource.new('localhost', 4484)
    @source.start
    @source.send_broadcast_event

    eventually do
      expect(@subscriber.received_broadcast_event?).to eq true
    end
  end

  after do
    puts 'tearing down test setup'
    Process.kill(:INT, @runnerpid)
    @subscriber.stop
  end
end

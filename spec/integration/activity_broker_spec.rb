require 'spec_helper'
require 'socket'

module AsyncHelper
  def eventually(options = {})
    timeout = options[:timeout]   || 5
    interval = options[:interval] || 0.1
    time_limit = Time.now + timeout
    loop do
      begin
        puts 'calling code'
        yield
      rescue => error
      end
      return if error.nil?
      if Time.now >= time_limit
        puts 'Test timeout exceeded'
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
    end

    def stop
      @connection.close
    end
  end

  class Queue
    def self.create
      readable_pipe_sender, writable_pipe_sender = IO.pipe
      new(readable_pipe_sender, writable_pipe_sender)
    end

    def initialize(to_read, to_write)
      @to_read  = to_read
      @to_write = to_write
    end

    def pop
      if message = @to_read.gets(CRLF)
        return message
      end
    end

    def pop!
      loop do
        if message = @to_read.gets(CRLF)
          return message
        end
      end
    end

    def push(message)
      @to_write.write(message)
    end
  end

  class ApplicationRunner
    def initialize(config)
      @config = config
    end

    def start
      event_source_queue = Queue.create
      delivery_queue     = Queue.create
      subscribers_queue  = Queue.create

      event_source_exchange = Exchange.new(@config[:event_source_exchange_port], event_source_queue, nil)
      delivery_exchange  = Exchange.new(@config[:subscriber_exchange_port], subscribers_queue, delivery_queue)

      @pid1 = fork do
        event_source_exchange.monitor
      end

      @pid2 = fork do
        delivery_exchange.monitor
      end

      @pid3 = fork do
        while message = event_source_queue.pop
          delivery_queue.push(message)
          puts %{Master received message #{message}}
        end
      end
    end

    def stop
      puts %{Killing exchange #{@pid1}}
      Process.kill(:INT, @pid1)
      puts %{Killing exchange #{@pid2}}
      Process.kill(:INT, @pid2)
      puts %{Killing forwarder #{@pid3}}
      Process.kill(:INT, @pid3)
    end
  end

  class EventSourceExchangeLogger

  end

  class SubscriberExchangeLogger

  end

  class Exchange
    attr_accessor :children

    def initialize(port, incoming_queue, outgoing_queue)
      @port = port
      @children = []
      @incoming_queue = incoming_queue
      @outgoing_queue = outgoing_queue
    end

    def monitor
      @server = TCPServer.new(@port)
      puts 'started tcp server on ' + @port.to_s

      trap_signal(:INT)

      loop do
        puts 'running accept loop'
        @connection = @server.accept
        listen_for_messages_to_forward if @outgoing_queue
        pid = fork do
          loop do
            puts 'running read loop ' + Process.pid.to_s
            message = @connection.gets(CRLF)
            if message
              puts "I got a message! " + message
              @incoming_queue.push(message)
            end
          end
        end
        @children << pid
      end
    end

    def listen_for_messages_to_forward
      pid = fork do
        puts 'waiting for messages to forward on' + Process.pid.to_s
        while message_to_forward = @outgoing_queue.pop
          @connection.write(message_to_forward)
          puts 'Forwarded message' + message_to_forward
        end
      end
      @children << pid
    end

    def trap_signal(signal)
      trap(signal) do
        puts 'interrupting exchange ' + Process.pid.to_s
        @children.each do |cpid|
          Process.kill(:INT, cpid)
        end
        exit
      end
    end
  end

  class FakeSubscriber
    def initialize(client_id, address, port)
      @client_id = client_id
      @address = address
      @port = port
      @children = []
      @events = []
    end

    def start
      @connection = Socket.tcp(@address, @port)
      @readable_pipe, @writable_pipe = IO.pipe
      pid = fork do
        loop do
          puts 'subscriber read loop'
          event = @connection.gets(CRLF)
          if event
            @events << event
            puts "received event from broker " + event
            @writable_pipe.write(event)
          else
            @connection.close
            break
          end
        end
      end
      @children << pid
      puts 'subscriber pid' + pid.to_s
    end

    def send_id
      @connection.write(@client_id)
      @connection.write(CRLF)
    end

    def received_broadcast_event?
      if message = @readable_pipe.gets(CRLF).gsub(CRLF, '')
        puts 'Parent received event from broker' + message
        message == '1|B'
      end
    end

    def stop
      @connection.close
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

    @runner.start

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
    puts 'SHUTTING DOWN'
    @runner.stop
  end
end

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
      @event_id = 0
    end

    def start
      @connection = Socket.tcp(@host, @port)
    end

    def publish_broadcast_event(options = {})
      publish_event('|B', options)
    end

    def publish_new_follower_to(recipient, sender, options = {})
      publish_event('|F|' + sender + '|' + recipient, options)
    end

    def publish_status_update_from(sender, options = {})
      publish_event('|S|' + sender, options)
    end

    def publish_private_message_to(recipient, sender, options = {})
      publish_event('|P|' + sender + '|' + recipient, options)
    end

    def publish_unfollow_to(recipient, sender, options = {})
      publish_event('|U|' + sender + '|' + recipient)
    end

    def publish_event(message, options = {})
      full_message = options.fetch(:id, event_id).to_s + message
      puts 'publishing event: ' + full_message
      @connection.write(full_message)
      @connection.write(CRLF)
      full_message
    end

    def event_id
      @event_id += 1
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
      event_forwarder = NotificationForwarder.new(@config.fetch(:logger){ Logger.new }, NotificationDelivery.new)

      @event_source_server.accept_connections do |message_stream|
        translator = NotificationTranslator.new(event_forwarder)
        unpacker   = EventSourceMessageUnpacker.new(NotificationOrdering.new(translator))
        message_stream.start_reading(unpacker)
      end

      @subscriber_server.accept_connections do |message_stream|
        message_stream.start_reading(SubscriberMessageTranslator.new(event_forwarder))
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
      puts 'connection accepted on server'
      @connection_listener.call(MessageStream.new(connection, @io_loop))
    end
  end

  class NotificationDelivery
    def initialize
      @subscribers = {}
    end

    def add_subscriber(subscriber_id, subscriber_stream)
      @subscribers[subscriber_id] = subscriber_stream
    end

    def deliver_message_to(recipient, message)
      @subscribers.fetch(recipient).write(message)
    end

    def deliver_message_to_everyone(message)
      @subscribers.each do |subscriber_id, subscriber_stream|
        subscriber_stream.write(message)
      end
    end
  end

  class NotificationForwarder
    def initialize(logger, notification_delivery)
      @followers   = Hash.new{ |hash, key| hash[key] = [] }
      @delivery = notification_delivery
      @logger = logger
    end

    def register_subscriber(subscriber_id, subscriber_stream)
      puts 'client_id_received ' + subscriber_id
      delivery.add_subscriber(subscriber_id, subscriber_stream)
      delivery.deliver_message_to(subscriber_id, 'welcome')
    end

    def process_broadcast_event(notification)
      puts 'forwarding broadcast ' + notification.id.to_s
      delivery.deliver_message_to_everyone(notification.message)
    end

    def process_follow_event(notification)
      puts 'forwarding follow event to ' + notification.recipient
      add_follower(notification.sender, notification.recipient)
      delivery.deliver_message_to(notification.recipient, notification.message)
    end

    def process_unfollow_event(notification)
      puts 'forwarding unfollow event recipient ' + notification.recipient
      remove_follower(notification.sender, notification.recipient)
      delivery.deliver_message_to(notification.recipient, notification.message)
    end

    def process_status_update_event(notification)
      @followers.fetch(notification.sender).each do |follower|
        delivery.deliver_message_to(follower, notification.message)
      end
    end

    def process_private_message_event(notification)
      delivery.deliver_message_to(notification.recipient, notification.message)
    end

    private

    attr_reader :delivery

    def remove_follower(follower, followed)
      @followers[followed] = @followers[followed] - [follower]
    end

    def add_follower(follower, followed)
      @followers[followed] << follower
    end
  end

  EventNotification = Struct.new(:id, :type, :sender, :recipient, :message)

  class EventSourceMessageUnpacker
    def initialize(listener)
      @listener = listener
    end

    def process_message(message, source_event_stream)
      id, type, sender, recipient = message.split('|')
      notification = EventNotification.new(id.to_i, type, sender, recipient, message)
      @listener.process_notification(notification)
    end
  end

  class NotificationOrdering
    def initialize(listener)
      @listener = listener
      @last_notification = nil
      @notification_queue = []
    end

    def process_notification(current_notification)
      if is_this_the_next_notification?(current_notification)
        forward_notification(current_notification)
        @notification_queue.sort! { |x, y| y.id <=> x.id }
        process_queued_notifications
      else
        @notification_queue << current_notification
      end
    end

    private

    def process_queued_notifications
      notification = @notification_queue.shift
      if notification && is_this_the_next_notification?(notification)
        forward_notification(notification)
        process_queued_notifications
      elsif notification
        @notification_queue.unshift(notification)
      end
    end

    def forward_notification(notification)
      @listener.process_notification(notification)
      @last_notification = notification
    end

    def is_this_the_next_notification?(next_notification)
      @last_notification.nil? || (next_notification.id - @last_notification.id) == 1
    end
  end

  class SubscriberMessageTranslator
    def initialize(listener)
      @listener = listener
    end

    def process_message(message, subscriber_stream)
      @listener.register_subscriber(message, subscriber_stream)
    end
  end

  class NotificationTranslator
    def initialize(listener)
      @listener = listener
    end

    def process_notification(notification)
      case notification.type
      when 'B'
        @listener.process_broadcast_event(notification)
      when 'F'
        @listener.process_follow_event(notification)
      when 'U'
        @listener.process_unfollow_event(notification)
      when 'P'
        @listener.process_private_message_event(notification)
      when 'S'
        @listener.process_status_update_event(notification)
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

    def write(message)
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
        ready_reading, ready_writing, _ = IO.select(@reading, @writing, nil)
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
      @notifications = []
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

    def has_received_notification_of?(notification, *args)
      notification = notification.to_s
      if @notifications.include?(notification)
        true
      else
        read_ready, _, _ = IO.select([@connection], nil, nil, 0)
        if read_ready
          buffer = read_ready.first.read_nonblock(4096)
          buffer.split(CRLF).each do |notification|
            puts @client_id + ' got notification: ' + notification
            @notifications << notification
          end
        end
      end
    end

    def received_joined_ack?
      has_received_notification_of?('welcome')
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

    broadcast = source.publish_broadcast_event

    eventually do
      expect(bob).to have_received_notification_of(broadcast)
    end
  end

  specify 'Multiple subscribers are notified of broadcast event' do
    start_activity_broker

    subscribers = 10.times.map do |id|
      start_subscriber('alice' + id.to_s, 4485)
    end

    source.start

    broadcast = source.publish_broadcast_event

    eventually do
      subscribers.each do |subscriber|
        expect(subscriber).to have_received_notification_of(broadcast)
      end
    end
  end

  specify 'A subscriber is notified of new follower' do
    start_activity_broker

    bob   = start_subscriber('bob', 4485)
    alice = start_subscriber('alice', 4485)

    source.start

    new_follower = source.publish_new_follower_to('bob', 'alice')

    eventually do
      expect(bob).to have_received_notification_of(new_follower)
    end
  end

  specify 'Multiple subscribers are notified of new followers' do
    start_activity_broker

    bob     = start_subscriber('bob', 4485)
    alice   = start_subscriber('alice', 4485)
    robert  = start_subscriber('robert', 4485)

    source.start

    alice_following_bob  = source.publish_new_follower_to('bob', 'alice')
    robert_following_bob = source.publish_new_follower_to('bob', 'robert')

    robert_following_alice = source.publish_new_follower_to('alice', 'robert')
    bob_following_alice    = source.publish_new_follower_to('alice', 'bob')

    alice_following_robert = source.publish_new_follower_to('robert', 'alice')
    bob_following_robert   = source.publish_new_follower_to('robert', 'bob')

    eventually do
      expect(bob).to have_received_notification_of(alice_following_bob)
      expect(bob).to have_received_notification_of(robert_following_bob)

      expect(alice).to have_received_notification_of(robert_following_alice)
      expect(alice).to have_received_notification_of(bob_following_alice)

      expect(robert).to have_received_notification_of(alice_following_robert)
      expect(robert).to have_received_notification_of(bob_following_robert)
    end
  end

  specify 'Unfollowed notification is forwarded to subscriber' do
    start_activity_broker

    bob   = start_subscriber('bob', 4485)
    alice = start_subscriber('alice', 4485)

    source.start

    source.publish_new_follower_to('bob', 'alice')

    alice_unfollowed_bob = source.publish_unfollow_to('bob', 'alice')

    eventually do
      expect(bob).to have_received_notification_of(alice_unfollowed_bob)
    end
  end

  specify 'Subscriber is notified of a private message' do
    start_activity_broker

    bob   = start_subscriber('bob', 4485)
    alice = start_subscriber('alice', 4485)

    source.start

    private_message = source.publish_private_message_to('bob', 'alice')

    eventually do
      expect(bob).to have_received_notification_of(private_message)
    end
  end

  specify 'Followers are notified of status updates from the users they follow' do
    start_activity_broker

    bob   = start_subscriber('bob', 4485)
    alice = start_subscriber('alice', 4485)

    source.start

    source.publish_new_follower_to('bob', 'alice')
    bob_status_update = source.publish_status_update_from('bob')

    source.publish_new_follower_to('alice', 'bob')
    alice_status_update = source.publish_status_update_from('alice')

    eventually do
      expect(alice).to have_received_notification_of(bob_status_update)
      expect(bob).to have_received_notification_of(alice_status_update)
    end
  end

  specify 'A subscriber no longer receive updates from a user after unfollowing' do
    start_activity_broker

    bob   = start_subscriber('bob', 4485)
    alice = start_subscriber('alice', 4485)

    source.start

    source.publish_new_follower_to('bob', 'alice')
    bob_status_update = source.publish_status_update_from('bob')

    eventually do
      expect(alice).to have_received_notification_of(bob_status_update)
    end

    source.publish_unfollow_to('bob', 'alice')
    new_bob_status_update = source.publish_status_update_from('bob')

    eventually do
      expect(alice).not_to have_received_notification_of(new_bob_status_update)
    end
  end

  specify 'Subscribers receive notifications in order' do
    start_activity_broker

    bob   = start_subscriber('bob', 4485)
    alice = start_subscriber('alice', 4485)

    source.start

    robert_following_alice = source.publish_new_follower_to('alice', 'robert', id: 1)
    alice_following_bob = source.publish_new_follower_to('bob', 'alice', id: 2)
    newer_bob_status_update = source.publish_status_update_from('bob', id: 4)
    bob_status_update       = source.publish_status_update_from('bob', id: 3)

    eventually do
      expect(alice).to have_received_notification_of(robert_following_alice)
      expect(bob).to have_received_notification_of(alice_following_bob)
    end

    eventually do
      expect(alice).to have_received_notification_of(bob_status_update)
    end

    eventually do
      expect(alice).to have_received_notification_of(newer_bob_status_update)
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

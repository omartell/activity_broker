require 'spec_helper'
require 'support/async_helper'
require 'socket'
require 'logger'
require 'delegate'

describe 'Activity Broker' do
  include AsyncHelper
  CRLF = '/r/n'

  class FakeEventSource
    def initialize(host, port, logger)
      @host = host
      @port = port
      @event_id = 0
      @logger = logger
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

    def publish_event(event, options = {})
      full_message = options.fetch(:id, event_id).to_s + event
      @logger.notify(:publishing_event, full_message)
      @connection.write(full_message)
      @connection.write(CRLF)
      full_message
    end

    def stop
      @connection.close
    end

    private

    def event_id
      @event_id += 1
    end
  end

  class ApplicationRunner
    def initialize(config)
      @config = config
      @event_loop = EventLoop.new
      @logger = @config.fetch(:logger){ ApplicationLogger.new }
    end

    def listen
      @event_source_server = Server.new(@config[:event_source_exchange_port], @event_loop, @logger)
      @subscriber_server   = Server.new(@config[:subscriber_exchange_port], @event_loop, @logger)
    end

    def start
      forwarder = NotificationForwarder.new(NotificationDelivery.new, @logger)
      event_notification_translator = NotificationTranslator.new(forwarder)
      ordering = NotificationOrdering.new(event_notification_translator)
      unpacker = EventSourceMessageUnpacker.new(ordering)

      @event_source_server.accept_connections do |message_stream|
        message_stream.read(unpacker)
      end

      subscriber_translator = SubscriberMessageTranslator.new(forwarder)
      @subscriber_server.accept_connections do |message_stream|
        message_stream.read(subscriber_translator)
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
    def initialize(port, io_loop, logger)
      @port = port
      @io_loop = io_loop
      @logger = logger
    end

    def accept_connections(&connection_accepted_listener)
      @logger.notify(:server_accepting_connections, @port)
      @server = TCPServer.new(@port)
      @connection_accepted_listener = connection_accepted_listener
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
      @logger.notify(:connection_accepted, @port)
      @connection_accepted_listener.call(MessageStream.new(connection, @io_loop, @logger))
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
      if subscriber = @subscribers[recipient]
        subscriber.write(message)
      end
    end

    def deliver_message_to_everyone(message)
      @subscribers.each do |subscriber_id, subscriber_stream|
        subscriber_stream.write(message)
      end
    end
  end

  class NotificationForwarder
    def initialize(notification_delivery, logger)
      @followers = Hash.new { |hash, key| hash[key] = [] }
      @delivery = notification_delivery
      @logger = logger
    end

    def register_subscriber(subscriber_id, subscriber_stream)
      @delivery.add_subscriber(subscriber_id, subscriber_stream)
      @delivery.deliver_message_to(subscriber_id, 'welcome')
      @logger.notify(:registering_subscriber, subscriber_id)
    end

    def process_broadcast_event(notification)
      @delivery.deliver_message_to_everyone(notification.message)
      @logger.notify(:forwarding_broadcast_event, notification)
    end

    def process_follow_event(notification)
      add_follower(notification.sender, notification.recipient)
      @delivery.deliver_message_to(notification.recipient, notification.message)
      @logger.notify(:forwarding_follow_event, notification)
    end

    def process_unfollow_event(notification)
      remove_follower(notification.sender, notification.recipient)
      @delivery.deliver_message_to(notification.recipient, notification.message)
      @logger.notify(:forwarding_unfollow_event, notification)
    end

    def process_status_update_event(notification)
      @followers.fetch(notification.sender).each do |follower|
        @delivery.deliver_message_to(follower, notification.message)
      end
      @logger.notify(:forwarding_unfollow_event, notification)
    end

    def process_private_message_event(notification)
      @delivery.deliver_message_to(notification.recipient, notification.message)
      @logger.notify(:forwarding_private_message, notification)
    end

    private

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
    def initialize(next_notification_listener)
      @next_notification_listener = next_notification_listener
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
      @next_notification_listener.process_notification(notification)
      @last_notification = notification
    end

    def is_this_the_next_notification?(next_notification)
      @last_notification.nil? || (next_notification.id - @last_notification.id) == 1
    end
  end

  class SubscriberMessageTranslator
    def initialize(translated_message_listener)
      @translated_message_listener = translated_message_listener
    end

    def process_message(message, subscriber_stream)
      @translated_message_listener.register_subscriber(message, subscriber_stream)
    end
  end

  class NotificationTranslator
    def initialize(notification_listener)
      @notification_listener = notification_listener
    end

    def process_notification(notification)
      case notification.type
      when 'B'
        @notification_listener.process_broadcast_event(notification)
      when 'F'
        @notification_listener.process_follow_event(notification)
      when 'U'
        @notification_listener.process_unfollow_event(notification)
      when 'P'
        @notification_listener.process_private_message_event(notification)
      when 'S'
        @notification_listener.process_status_update_event(notification)
      end
    end
  end

  class MessageStream
    def initialize(io, io_loop, logger)
      @io = io
      @io_loop = io_loop
      @logger = logger
      @read_buffer = ''
    end

    def read(message_listener)
      @message_listener = message_listener
      @io_loop.register_read(self, :data_received)
    end

    def to_io
      @io
    end

    def write(message)
      @io.write(message)
      @io.write(CRLF)
    end

    private

    def data_received
      begin
        @read_buffer << @io.read_nonblock(4096)
        forward_messages
      rescue IO::WaitReadable
        # IO isn't actually readable.
      rescue EOFError, Errno::ECONNRESET
        # Connection closed
      end
    end

    def forward_messages
      message_regex = /([^\/]*)\/r\/n/

      @read_buffer.scan(message_regex).flatten.each do |m|
        @logger.notify(:streaming_message, m)
        @message_listener.process_message(m, self)
      end
      @read_buffer = @read_buffer.gsub(message_regex, "")
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

  class ApplicationLogger
    def initialize(output, level = Logger::INFO)
      @logger = Logger.new(output)
      @logger.datetime_format = "%Y-%m-%d %H:%M:%S"
      @logger.level = level
    end

    def notify(event, *other)
      send(event, *other)
    end

    private

    def server_accepting_connections(port)
      log_info('server accepting connections on port ' + port.to_s)
    end

    def connection_accepted(port)
      log_info('connection accepted on port ' + port.to_s)
    end

    def streaming_message(message)
      log_info('streaming message ' + message)
    end

    def registering_subscriber(subscriber_id)
      log_info('registering subscriber ' + subscriber_id)
    end

    def forwarding_broadcast_event(notification)
      log_info('forwarding broadcast event: ' + notification.message)
    end

    def forwarding_follow_event(notification)
      log_info('forwarding follow event: ' + notification.message)
    end

    def forwarding_unfollow_event(notification)
      log_info('forwarding unfollow event: ' + notification.message)
    end

    def forwarding_private_message(notification)
      log_info('forwarding private message: ' + notification.message)
    end

    def log_info(message)
      @logger.info(message)
    end
  end

  class TestLogger < ApplicationLogger
    private

    def publishing_event(message)
      log_info('publishing event: ' + message)
    end

    def sending_subscriber_id(subscriber_id)
      log_info('sending subscriber id: ' + subscriber_id)
    end

    def receiving_notification(notification, subscriber_id)
      log_info(subscriber_id + ' received notification: ' + notification)
    end
  end

  class FakeSubscriber
    def initialize(client_id, address, port, logger)
      @client_id = client_id
      @address = address
      @port = port
      @logger = logger
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
      @logger.notify(:sending_subscriber_id, @client_id)
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
            @logger.notify(:receiving_notification, notification, @client_id)
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
                            logger: test_logger }).tap do |a|
      a.listen
    end
  end

  let!(:source) do
    FakeEventSource.new('0.0.0.0', 4484, test_logger)
  end

  let!(:test_logger) do
    TestLogger.new(STDOUT, Logger::INFO)
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

  specify 'Subscribers receive event notifications in order' do
    start_activity_broker

    bob   = start_subscriber('bob', 4485)
    alice = start_subscriber('alice', 4485)

    source.start

    robert_following_alice = source.publish_new_follower_to('alice', 'robert', id: 1)
    alice_following_bob = source.publish_new_follower_to('bob', 'alice', id: 2)
    newer_bob_status_update = source.publish_status_update_from('bob', id: 4)

    eventually do
      expect(alice).to have_received_notification_of(robert_following_alice)
      expect(bob).to have_received_notification_of(alice_following_bob)
    end

    bob_status_update = source.publish_status_update_from('bob', id: 3)

    eventually do
      expect(alice).to have_received_notification_of(bob_status_update)
    end

    eventually do
      expect(alice).to have_received_notification_of(newer_bob_status_update)
    end
  end

  specify 'Event notifications are ignored if subscriber is not connected' do
    start_activity_broker

    bob = start_subscriber('bob', 4485)

    source.start

    alice_following_bob = source.publish_new_follower_to('bob', 'alice', id: 1)
    robert_following_alice = source.publish_new_follower_to('alice', 'robert', id: 2)

    eventually do
      expect(bob).to have_received_notification_of(alice_following_bob)
    end
  end

  def start_subscriber(id, port)
    FakeSubscriber.new(id, '0.0.0.0', port, test_logger).tap do |s|
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

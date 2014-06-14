require 'spec_helper'
require 'support/async_helper'
require 'socket'
require 'logger'
require 'delegate'

describe 'Activity Broker' do
  include AsyncHelper
  CRLF = '/r/n'

  class FakeEventSource
    def initialize(host, port, event_logger)
      @host = host
      @port = port
      @event_id = 0
      @event_logger = event_logger
    end

    def start
      @connection = Socket.tcp(@host, @port)
    end

    def publish_broadcast_event(id: nil)
      publish_event('B', id)
    end

    def publish_new_follower_to(recipient, sender, id: nil)
      publish_event('F', sender, recipient, id)
    end

    def publish_status_update_from(sender, id: nil)
      publish_event('S', sender, id)
    end

    def publish_private_message_to(recipient, sender, id: nil)
      publish_event('P', sender, recipient, id)
    end

    def publish_unfollow_to(recipient, sender, id: nil)
      publish_event('U', sender, recipient,  id)
    end

    def stop
      @event_logger.log(:stopping_event_source, @port)
      @connection.close
    end

    private

    def publish_event(*notification_args, id)
      notification_args.unshift(id || generate_event_id)
      full_message = notification_args.join('|')
      @event_logger.log(:publishing_event, full_message)
      @connection.write(full_message)
      @connection.write(CRLF)
      full_message
    end

    def generate_event_id
      @event_id += 1
    end
  end

  class ApplicationRunner
    def initialize(config)
      @config = config
      @event_logger = @config.fetch(:event_logger) do
        ApplicationEventLogger.new('/tmp/activity_broker.log', Logger::INFO)
      end
      @event_loop = EventLoop.new(@event_logger)
    end

    def start
      @event_source_server = start_server_on(:event_source_port)
      @subscriber_server   = start_server_on(:subscriber_port)
      notification_router     = NotificationRouter.new(NotificationDelivery.new, @event_logger)
      notification_translator = NotificationTranslator.new(notification_router)
      notification_ordering   = NotificationOrdering.new(notification_translator)
      message_unpacker        = EventSourceMessageUnpacker.new(notification_ordering)

      @event_source_server.accept_connections do |message_stream|
        message_stream.read(message_unpacker)
      end

      subscriber_translator = SubscriberMessageTranslator.new(notification_router)
      @subscriber_server.accept_connections do |message_stream|
        message_stream.read(subscriber_translator)
      end

      trap_signal
      @event_loop.start
    end

    def stop
      @event_source_server.stop
      @subscriber_server.stop
      @event_loop.stop
    end

    def trap_signal
      trap(:INT) do
        stop
        exit
      end
    end

    private

    def start_server_on(port)
      Server.new(@config.fetch(port), @event_loop, @event_logger)
    end
  end

  class Server
    def initialize(port, io_loop, event_logger)
      @port = port
      @io_loop = io_loop
      @event_logger = event_logger
      @message_streams = []
    end

    def accept_connections(&connection_accepted_listener)
      @event_logger.log(:server_accepting_connections, @port)
      @tcp_server = TCPServer.new(@port)
      @connection_accepted_listener = connection_accepted_listener
      @io_loop.register_read(self, :process_new_connection)
    end

    def to_io
      @tcp_server
    end

    def stop
      @io_loop.deregister_read(self, :process_new_connection)
      @message_streams.each(&:close)
      @tcp_server.close
    end

    def closed?
      @tcp_server.closed?
    end

    private

    def process_new_connection
      connection     = @tcp_server.accept_nonblock
      message_stream = MessageStream.new(connection, @io_loop, @event_logger, @port)
      @message_streams << message_stream
      @connection_accepted_listener.call(message_stream)
      @event_logger.log(:connection_accepted, @port)
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
      if subscriber_stream = @subscribers[recipient]
        subscriber_stream.write(message)
      end
    end

    def deliver_message_to_everyone(message)
      @subscribers.each do |subscriber_id, subscriber_stream|
        subscriber_stream.write(message)
      end
    end
  end

  class NotificationRouter
    def initialize(notification_delivery, event_logger)
      @followers = Hash.new { |hash, key| hash[key] = [] }
      @delivery = notification_delivery
      @event_logger = event_logger
    end

    def register_subscriber(subscriber_id, subscriber_stream)
      @delivery.add_subscriber(subscriber_id, subscriber_stream)
      log(:registering_subscriber, subscriber_id)
    end

    def process_broadcast_event(notification)
      @delivery.deliver_message_to_everyone(notification.message)
      log(:forwarding_broadcast_event, notification)
    end

    def process_follow_event(notification)
      add_follower(notification.sender, notification.recipient)
      @delivery.deliver_message_to(notification.recipient, notification.message)
      log(:forwarding_follow_event, notification)
    end

    def process_unfollow_event(notification)
      remove_follower(notification.sender, notification.recipient)
      @delivery.deliver_message_to(notification.recipient, notification.message)
      log(:forwarding_unfollow_event, notification)
    end

    def process_status_update_event(notification)
      @followers.fetch(notification.sender).each do |follower|
        @delivery.deliver_message_to(follower, notification.message)
      end
      log(:forwarding_status_update, notification)
    end

    def process_private_message_event(notification)
      @delivery.deliver_message_to(notification.recipient, notification.message)
      log(:forwarding_private_message, notification)
    end

    private

    def log(event, notification)
      @event_logger.log(event, notification)
    end

    def remove_follower(follower, followed)
      @followers[followed] = @followers[followed] - [follower]
    end

    def add_follower(follower, followed)
      @followers[followed] << follower
    end
  end

  class EventSourceMessageUnpacker

    EventNotification = Struct.new(:id, :type, :sender, :recipient, :message)

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
    def initialize(io, io_loop, event_logger, port)
      @io = io
      @io_loop = io_loop
      @event_logger = event_logger
      @read_buffer  = ''
      @write_buffer = ''
      @port = port
    end

    def read(message_listener)
      @message_listener = message_listener
      @io_loop.register_read(self, :data_received)
    end

    def to_io
      @io
    end

    def write(message)
      @write_buffer << message
      @write_buffer << CRLF
      @io_loop.register_write(self, :ready_to_write)
    end

    def close
      @closed = true
      @io_loop.deregister_write(self, :ready_to_write)
      @io_loop.deregister_read(self, :data_received)
      @io.close unless @closed
    end

    def closed?
      @closed
    end

    private

    def ready_to_write
      begin
        bytes_written = @io.write_nonblock(@write_buffer)
        @write_buffer.slice!(0, bytes_written)
        if @write_buffer.empty?
          @io_loop.deregister_write(self, :ready_to_write)
        end
      rescue Errno::EAGAIN
        # write would actually block
      end
    end

    def data_received
      begin
        unless @closed
          @read_buffer << @io.read_nonblock(4096)
          forward_messages
        end
      rescue IO::WaitReadable
        # IO isn't actually readable.
      rescue EOFError
        # No more data coming from the other end
        self.close
      end
    end

    def forward_messages
      message_regex = /([^\/]*)\/r\/n/
      @read_buffer.scan(message_regex).flatten.each do |m|
        @event_logger.log(:streaming_message, m)
        @message_listener.process_message(m, self)
      end
      @read_buffer = @read_buffer.gsub(message_regex, '')
    end
  end

  class EventLoop
    def initialize(event_logger)
      @reading = []
      @writing = []
      @event_logger  = event_logger
    end

    def start
      loop do
        ready_reading, ready_writing, _ = IO.select(@reading, @writing, nil, 0)
        ((ready_writing || []) + (ready_reading || [])).each(&:log)

        if @stop
          @event_logger.log(:shutting_down_reactor)
          break
        end
      end
    end

    def register_read(listener, event = nil, &block)
      io_listener = new_io_listener(listener, event, block)
      if !@reading.include?(io_listener)
        @reading << io_listener
      end
    end

    def register_write(listener, event = nil, &block)
      io_listener = new_io_listener(listener, event, block)
      if !@writing.include?(io_listener)
        @writing << io_listener
      end
    end

    def stop
      @stop = true
    end

    def deregister_write(listener, event = nil, &block)
      @writing.delete(new_io_listener(listener, event, block))
    end

    def deregister_read(listener, event = nil, &block)
      @reading.delete(new_io_listener(listener, event, block))
    end

    private

    def new_io_listener(listener, event, block)
      IOListener.new(listener, event, block)
    end
  end

  class IOListener
    attr_reader :listener, :event, :block
    def initialize(listener, event, block)
      @listener = listener
      @event = event
      @block = block
    end

    def to_io
      @listener.to_io
    end

    def ==(other_io_listener)
      self.event == other_io_listener.event &&
      self.listener == other_io_listener.listener &&
      self.block == other_io_listener.block
    end

    def log
      if @event
        @listener.send(@event)
      else
        @block.call(@listener)
      end
    end
  end

  class ApplicationEventLogger
    def initialize(output, level = Logger::INFO)
      @logger = Logger.new(output)
      @logger.datetime_format = "%Y-%m-%d %H:%M:%S"
      @logger.level = level
      @events = []
    end

    def log(event, *other)
      @events << event
      send(event, *other)
    end

    def registered_event?(event)
      @events.include?(event)
    end

    private

    def log_info(message)
      @logger.info(message)
    end

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

    def forwarding_status_update(notification)
      log_info('forwarding status update: ' + notification.message)
    end

    def forwarding_private_message(notification)
      log_info('forwarding private message: ' + notification.message)
    end

    def stopping_server(port)
      log_info('stopping server on port ' + port.to_s)
    end

    def stopping_event_source(port)
      log_info('stopping event source on port ' + port.to_s)
    end

    def stopping_subscriber(client_id, port)
      log_info('stopping subscriber ' + client_id + ' on port ' + port.to_s )
    end

    def received_interrupt_signal
      log_info('interrupting execution')
    end

    def handling_thread_interrupt
      log_info('handling thread interrupt')
    end

    def shutting_down_reactor
      log_info('activity broker shutdown')
    end
  end

  class TestEventLogger < ApplicationEventLogger

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
    def initialize(client_id, address, port, event_logger)
      @client_id = client_id
      @address = address
      @port = port
      @event_logger = event_logger
      @notifications = []
    end

    def start
      begin
        @connection = Socket.tcp(@address, @port)
      rescue Errno::ECONNREFUSED
        retry
      end
    end

    def closed?
      @connection.closed?
    end

    def send_client_id
      @connection.write(@client_id)
      @connection.write(CRLF)
      @event_logger.log(:sending_subscriber_id, @client_id)
    end

    def has_received_notification_of?(notification)
      if @notifications.include?(notification.to_s)
        true
      else
        read_notifications
        false
      end
    end

    def stop
      @event_logger.log(:stopping_subscriber, @client_id, @port)
      @connection.close
    end

    private

    def read_notifications
      read_ready, _, _ = IO.select([@connection], nil, nil, 0)
      if read_ready
        begin
          buffer = read_ready.first.read_nonblock(4096)
          buffer.split(CRLF).each do |notification|
            @event_logger.log(:receiving_notification, notification, @client_id)
            @notifications << notification
          end
        rescue EOFError
          # broker closed connection
        end
      end
    end
  end

  let!(:test_logger) { TestEventLogger.new('/tmp/activity_broker.log', Logger::INFO)  }
  let!(:event_source) { FakeEventSource.new('0.0.0.0', 4484, test_logger) }
  let!(:activity_broker) do
    ApplicationRunner.new({ event_source_port: 4484,
                            subscriber_port: 4485,
                            event_logger: test_logger })
  end
  let!(:subscribers) { [ ] }

  def start_activity_broker
    @thread = Thread.new { activity_broker.start }
    @thread.abort_on_exception = true
  end

  def start_subscriber(id)
    FakeSubscriber.new(id, '0.0.0.0', 4485, test_logger).tap do |subscriber|
      subscriber.start
      subscriber.send_client_id
      subscribers << subscriber
    end
  end

  after do
    event_source.stop
    subscribers.each(&:stop)
    eventually { expect(subscribers.all?(&:closed?)).to eq true }
    activity_broker.stop
    eventually { expect(test_logger.registered_event?(:shutting_down_reactor)).to eq true }
  end

  specify 'A subscriber is notified of broadcast event' do
    start_activity_broker

    bob = start_subscriber('bob')

    event_source.start

    broadcast = event_source.publish_broadcast_event

    eventually do
      expect(bob).to have_received_notification_of(broadcast)
    end
  end

  specify 'Multiple subscribers are notified of broadcast event' do
    start_activity_broker

    subscribers = 10.times.map do |id|
      start_subscriber('alice' + id.to_s)
    end

    event_source.start

    broadcast = event_source.publish_broadcast_event

    eventually do
      subscribers.each do |subscriber|
        expect(subscriber).to have_received_notification_of(broadcast)
      end
    end
  end

  specify 'A subscriber is notified of new follower' do
    start_activity_broker

    bob   = start_subscriber('bob')
    alice = start_subscriber('alice')

    event_source.start

    new_follower = event_source.publish_new_follower_to('bob', 'alice')

    eventually do
      expect(bob).to have_received_notification_of(new_follower)
    end
  end

  specify 'Multiple subscribers are notified of new followers' do
    start_activity_broker

    bob     = start_subscriber('bob')
    alice   = start_subscriber('alice')
    robert  = start_subscriber('robert')

    event_source.start

    alice_following_bob  = event_source.publish_new_follower_to('bob', 'alice')
    robert_following_bob = event_source.publish_new_follower_to('bob', 'robert')

    robert_following_alice = event_source.publish_new_follower_to('alice', 'robert')
    bob_following_alice    = event_source.publish_new_follower_to('alice', 'bob')

    alice_following_robert = event_source.publish_new_follower_to('robert', 'alice')
    bob_following_robert   = event_source.publish_new_follower_to('robert', 'bob')

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

    bob   = start_subscriber('bob')
    alice = start_subscriber('alice')

    event_source.start

    event_source.publish_new_follower_to('bob', 'alice')

    alice_unfollowed_bob = event_source.publish_unfollow_to('bob', 'alice')

    eventually do
      expect(bob).to have_received_notification_of(alice_unfollowed_bob)
    end
  end

  specify 'Subscriber is notified of a private message' do
    start_activity_broker

    bob   = start_subscriber('bob')
    alice = start_subscriber('alice')

    event_source.start

    private_message = event_source.publish_private_message_to('bob', 'alice')

    eventually do
      expect(bob).to have_received_notification_of(private_message)
    end
  end

  specify 'Followers are notified of status updates from the users they follow' do
    start_activity_broker

    bob   = start_subscriber('bob')
    alice = start_subscriber('alice')

    event_source.start

    event_source.publish_new_follower_to('bob', 'alice')
    bob_status_update = event_source.publish_status_update_from('bob')

    event_source.publish_new_follower_to('alice', 'bob')
    alice_status_update = event_source.publish_status_update_from('alice')

    eventually do
      expect(alice).to have_received_notification_of(bob_status_update)
      expect(bob).to have_received_notification_of(alice_status_update)
    end
  end

  xspecify 'A subscriber no longer receive updates from a user after unfollowing' do
    start_activity_broker

    bob   = start_subscriber('bob')
    alice = start_subscriber('alice')

    event_source.start

    event_source.publish_new_follower_to('bob', 'alice')
    bob_status_update = event_source.publish_status_update_from('bob')

    eventually do
      expect(alice).to have_received_notification_of(bob_status_update)
    end

    event_source.publish_unfollow_to('bob', 'alice')
    new_bob_status_update = event_source.publish_status_update_from('bob')

    eventually do
      # check that it really hasnt received notification
      expect(alice).not_to have_received_notification_of(new_bob_status_update)
    end
  end

  specify 'Subscribers receive event notifications in order' do
    start_activity_broker

    bob   = start_subscriber('bob')
    alice = start_subscriber('alice')

    event_source.start

    robert_following_alice = event_source.publish_new_follower_to('alice', 'robert', id: 1)
    alice_following_bob = event_source.publish_new_follower_to('bob', 'alice', id: 2)
    newer_bob_status_update = event_source.publish_status_update_from('bob', id: 4)

    eventually do
      expect(alice).to have_received_notification_of(robert_following_alice)
      expect(bob).to have_received_notification_of(alice_following_bob)
    end

    bob_status_update = event_source.publish_status_update_from('bob', id: 3)

    eventually do
      expect(alice).to have_received_notification_of(bob_status_update)
    end

    eventually do
      expect(alice).to have_received_notification_of(newer_bob_status_update)
    end
  end

  specify 'Event notifications are ignored if subscriber is not connected' do
    start_activity_broker

    bob = start_subscriber('bob')

    event_source.start

    alice_following_bob = event_source.publish_new_follower_to('bob', 'alice', id: 1)
    robert_following_alice = event_source.publish_new_follower_to('alice', 'robert', id: 2)

    eventually do
      expect(bob).to have_received_notification_of(alice_following_bob)
    end
  end
end

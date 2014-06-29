require 'spec_helper'
require 'support/async_helper'
require_relative '../../lib/activity_broker'

describe 'Activity Broker' do
  include AsyncHelper

  class FakeEventSource
    def initialize(host, port, event_logger)
      @host = host
      @port = port
      @event_id = 0
      @event_logger = event_logger
    end

    def start
      @connection = TCPSocket.new(@host, @port)
    end

    def publish_broadcast_event(options = {})
      publish_event('B', options[:id])
    end

    def publish_new_follower_to(recipient, sender, options = {})
      publish_event('F', sender, recipient, options[:id])
    end

    def publish_status_update_from(sender, options = {})
      publish_event('S', sender, options[:id])
    end

    def publish_private_message_to(recipient, sender, options = {})
      publish_event('P', sender, recipient, options[:id])
    end

    def publish_unfollow_to(recipient, sender, options = {})
      publish_event('U', sender, recipient, options[:id])
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
      @connection.write(ActivityBroker::MessageStream::MESSAGE_BOUNDARY)
      full_message
    end

    def generate_event_id
      @event_id += 1
    end
  end

  class TestEventLogger < ActivityBroker::ApplicationEventLogger

    def initialize(output, level = Logger::DEBUG)
      @events = []
      super(output, level)
    end

    def has_received_event?(event, *other)
      event_data = [event] + other
      @events.include?(event_data)
    end

    def log(event, *other)
      @events << ([event] + other)
      super(event, *other)
    end

    def publishing_event(message)
      log_debug('publishing event: ' + message)
    end

    def sending_subscriber_id(subscriber_id)
      log_debug('sending subscriber id: ' + subscriber_id)
    end

    def receiving_notification(notification, subscriber_id)
      log_debug(subscriber_id + ' received notification: ' + notification)
    end

    def stopping_event_source(port)
      log_debug('stopping event source on port ' + port.to_s)
    end

    def stopping_subscriber(client_id, port)
      log_debug('stopping subscriber ' + client_id + ' on port ' + port.to_s )
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
        @connection = TCPSocket.new(@address, @port)
      rescue Errno::ECONNREFUSED
        retry
      end
    end

    def closed?
      @connection.closed?
    end

    def send_client_id
      @connection.write(@client_id)
      @connection.write(ActivityBroker::MessageStream::MESSAGE_BOUNDARY)
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
          buffer.split(ActivityBroker::MessageStream::MESSAGE_BOUNDARY).each do |notification|
            @event_logger.log(:receiving_notification, notification, @client_id)
            @notifications << notification
          end
        rescue EOFError
          # broker closed connection
        end
      end
    end
  end

  let!(:test_logger) { TestEventLogger.new('/tmp/activity_broker.log', Logger::DEBUG)  }
  let!(:event_source) { FakeEventSource.new('0.0.0.0', 4484, test_logger) }
  let!(:activity_broker) do
    ActivityBroker::ApplicationRunner.new({ event_source_port: 4484,
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
      wait_until do
        expect(test_logger).to have_received_event(:registering_subscriber, id)
      end
    end
  end

  after do
    event_source.stop
    subscribers.each(&:stop)
    activity_broker.stop
    wait_until do
      expect(test_logger).to have_received_event(:stopping_event_loop)
    end
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

  specify 'Unfollowed notifications are not forwarded to subscribers' do
    start_activity_broker

    bob   = start_subscriber('bob')
    alice = start_subscriber('alice')

    event_source.start

    event_source.publish_new_follower_to('bob', 'alice')

    alice_unfollowed_bob = event_source.publish_unfollow_to('bob', 'alice')

    eventually do
      expect(test_logger).to have_received_event(:discarding_unfollow_event,
                                                 alice_unfollowed_bob)
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

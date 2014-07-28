require 'spec_helper'
require 'support/async_helper'
require_relative '../../lib/activity_broker'

describe 'Activity Broker' do
  include AsyncHelper

  let!(:event_source) { FakeEventSource.new('0.0.0.0', 4484, test_logger) }
  let!(:activity_broker) do
    ActivityBroker::ApplicationRunner.new({ event_source_port: 4484,
                                            subscriber_port: 4485,
                                            event_logger: test_logger })
  end
  let!(:test_logger) do
    TestEventLogger.new('/tmp/activity_broker.log', Logger::DEBUG)
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

  specify 'All subscribers are notified of broadcast event' do
    start_activity_broker

    subscribers = 10.times.map do |id|
      start_subscriber('123' + id.to_s)
    end

    event_source.start

    broadcast = event_source.publish_broadcast_event

    eventually do
      subscribers.each do |subscriber|
        expect(subscriber).to have_received_notification_of(broadcast)
      end
    end
  end

  specify 'Subscribers are notified of new followers' do
    start_activity_broker

    bob     = start_subscriber('456')
    alice   = start_subscriber('123')
    robert  = start_subscriber('789')

    event_source.start

    alice_following_bob  = event_source.publish_new_follower_to('456', '123')
    robert_following_bob = event_source.publish_new_follower_to('456', '789')

    robert_following_alice = event_source.publish_new_follower_to('123', '789')
    bob_following_alice    = event_source.publish_new_follower_to('123', '456')

    alice_following_robert = event_source.publish_new_follower_to('789', '123')
    bob_following_robert   = event_source.publish_new_follower_to('789', '456')

    eventually do
      expect(bob).to have_received_notification_of(alice_following_bob)
      expect(bob).to have_received_notification_of(robert_following_bob)

      expect(alice).to have_received_notification_of(robert_following_alice)
      expect(alice).to have_received_notification_of(bob_following_alice)

      expect(robert).to have_received_notification_of(alice_following_robert)
      expect(robert).to have_received_notification_of(bob_following_robert)
    end
  end

  specify 'Subscribers are not notified when people stop following them' do
    start_activity_broker

    bob   = start_subscriber('456')
    alice = start_subscriber('123')

    event_source.start

    alice_following_bob = event_source.publish_new_follower_to('456', '123')

    eventually do
      expect(bob).to have_received_notification_of(alice_following_bob)
    end

    alice_unfollowed_bob = event_source.publish_unfollow_to('456', '123')

    eventually do
      expect(test_logger).to have_received_event(:discarding_unfollow_event,
                                                 alice_unfollowed_bob)
    end
  end

  specify 'Subscribers are notified of private messages' do
    start_activity_broker

    bob   = start_subscriber('456')
    alice = start_subscriber('123')

    event_source.start

    private_message = event_source.publish_private_message_to('456', '123')

    eventually do
      expect(bob).to have_received_notification_of(private_message)
    end
  end

  specify 'Followers are notified of status updates from users they follow' do
    start_activity_broker

    bob   = start_subscriber('456')
    alice = start_subscriber('123')

    event_source.start

    event_source.publish_new_follower_to('456', '123')
    bob_status_update = event_source.publish_status_update_from('456')

    event_source.publish_new_follower_to('123', '456')
    alice_status_update = event_source.publish_status_update_from('123')

    eventually do
      expect(alice).to have_received_notification_of(bob_status_update)
      expect(bob).to have_received_notification_of(alice_status_update)
    end
  end

  specify 'A subscriber no longer receives updates after unfollowing' do
    start_activity_broker

    bob   = start_subscriber('456')
    alice = start_subscriber('123')

    event_source.start

    alice_following_bob = event_source.publish_new_follower_to('456', '123')
    bob_status_update = event_source.publish_status_update_from('456')

    eventually do
      expect(bob).to have_received_notification_of(alice_following_bob)
      expect(alice).to have_received_notification_of(bob_status_update)
    end

    alice_unfollowed_bob = event_source.publish_unfollow_to('456', '123')

    eventually do
      expect(test_logger).to have_received_event(:discarding_unfollow_event,
                                                 alice_unfollowed_bob)
    end

    new_bob_status_update = event_source.publish_status_update_from('456')

    eventually do
      expect(alice).not_to have_received_notification_of(new_bob_status_update)
    end
  end

  specify 'Subscribers receive notifications in order' do
    start_activity_broker

    bob   = start_subscriber('456')
    alice = start_subscriber('123')

    event_source.start

    robert_following_alice = event_source.publish_new_follower_to('123', '789', id: 1)
    alice_following_bob = event_source.publish_new_follower_to('456', '123', id: 2)
    newer_bob_status_update = event_source.publish_status_update_from('456', id: 4)

    eventually do
      expect(alice).to have_received_notification_of(robert_following_alice)
      expect(bob).to have_received_notification_of(alice_following_bob)
    end

    bob_status_update = event_source.publish_status_update_from('456', id: 3)

    eventually do
      expect(alice).to have_received_notification_of(bob_status_update)
    end

    eventually do
      expect(alice).to have_received_notification_of(newer_bob_status_update)
    end
  end

  specify 'Event notifications are ignored if subscriber is not connected' do
    start_activity_broker

    bob = start_subscriber('456')

    event_source.start

    alice_following_bob = event_source.publish_new_follower_to('456', '123', id: 1)
    robert_following_alice = event_source.publish_new_follower_to('123', '789', id: 2)

    eventually do
      expect(bob).to have_received_notification_of(alice_following_bob)
    end
  end
end

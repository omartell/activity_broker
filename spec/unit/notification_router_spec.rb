require 'spec_helper'

module ActivityBroker
  describe NotificationRouter do
    let!(:notification_delivery) { double(add_subscriber: nil, deliver_message_to: nil) }
    let!(:notification_router) { NotificationRouter.new(notification_delivery,
                                                        double.as_null_object) }
    let!(:alice_following_bob) { EventNotification.new(1, 'F', 'alice', 'bob', '1|F|alice|bob') }

    let!(:bob_status_update) { EventNotification.new(2, 'S', 'bob', '2|S|bob', '2|S|bob') }

    it 'forwards status updates to followers' do
      notification_router.register_subscriber('bob', double(write: nil))

      expect(notification_delivery).to receive(:deliver_message_to)
        .with('bob', alice_following_bob.message)

      notification_router.process_follow_event(alice_following_bob)

      expect(notification_delivery).to receive(:deliver_message_to)
        .with('alice', bob_status_update.message)

      notification_router.process_status_update_event(bob_status_update)
    end

    it 'stops forwarding status updates when subscribers unfollow' do
      notification_router.register_subscriber('bob', double(write: nil))
      notification_router.process_follow_event(alice_following_bob)
      notification_router.process_unfollow_event(alice_following_bob)

      expect(notification_delivery).not_to receive(:deliver_message_to)
        .with('alice', bob_status_update.message)

      notification_router.process_status_update_event(bob_status_update)
    end

    it 'processes status updates even when a subscriber has no followers' do
      notification = EventNotification.new(1, 'S', 'alice', nil, '1|S|alice')

      expect(notification_delivery).not_to receive(:deliver_message_to)

      notification_router.process_status_update_event(notification)
    end
  end
end

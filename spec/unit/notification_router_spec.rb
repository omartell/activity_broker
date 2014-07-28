require 'spec_helper'

module ActivityBroker
  describe NotificationRouter do
    let!(:notification_delivery) { double(add_subscriber: nil, deliver_message_to: nil) }
    let!(:notification_router) { NotificationRouter.new(notification_delivery,
                                                        double.as_null_object) }
    let!(:alice_following_bob) { Follower.new(id: 1, sender: 123, recipient: 456) }

    let!(:bob_status_update) { StatusUpdate.new(id: 2, sender: 456) }

    it 'forwards status updates to followers' do
      notification_router.register_subscriber(456, double(write: nil))

      expect(notification_delivery).to receive(:deliver_message_to)
        .with(456, alice_following_bob.message)

      notification_router.process_follow_event(alice_following_bob)

      expect(notification_delivery).to receive(:deliver_message_to)
        .with(123, bob_status_update.message)

      notification_router.process_status_update_event(bob_status_update)
    end

    it 'stops forwarding status updates when subscribers unfollow' do
      notification_router.register_subscriber(456, double(write: nil))
      notification_router.process_follow_event(alice_following_bob)
      notification_router.process_unfollow_event(alice_following_bob)

      expect(notification_delivery).not_to receive(:deliver_message_to)
        .with(123, bob_status_update.message)

      notification_router.process_status_update_event(bob_status_update)
    end

    it 'processes status updates even when a subscriber has no followers' do
      notification = StatusUpdate.new(id: 1, sender: 123)

      expect(notification_delivery).not_to receive(:deliver_message_to)

      notification_router.process_status_update_event(notification)
    end

    it 'does not register a follower twice' do
      alice_following_bob = Follower.new(id: 1, sender: 123, recipient: 456)

      expect(notification_delivery).to receive(:deliver_message_to)
        .with(456, alice_following_bob.message).once

      notification_router.process_follow_event(alice_following_bob)
      notification_router.process_follow_event(alice_following_bob)
    end
  end
end

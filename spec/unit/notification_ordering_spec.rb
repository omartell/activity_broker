require 'spec_helper'

module ActivityBroker
  describe NotificationOrdering do

    let(:notification_listener) { double(process_notification: nil) }
    let(:notification_ordering) do
      NotificationOrdering.new(notification_listener, double.as_null_object)
    end

    it 'forwards notifications in order' do
      first_status  = Broadcast.new(id: 1)
      second_status = Follower.new(id: 2, sender: 123, recipient: 456)
      third_status  = Follower.new(id: 3, sender: 123, recipient: 789)
      fourth_status = Unfollowed.new(id: 4, sender: 123, recipient: 789)
      fifth_status  = PrivateMessage.new(id: 5, sender: 123, recipient: 789)

      expect(notification_listener).to receive(:process_notification)
        .with(first_status).ordered
      expect(notification_listener).to receive(:process_notification)
        .with(second_status).ordered
      expect(notification_listener).to receive(:process_notification)
        .with(third_status).ordered

      notification_ordering.process_notification(first_status)
      notification_ordering.process_notification(third_status)
      notification_ordering.process_notification(fourth_status)
      notification_ordering.process_notification(fifth_status)
      notification_ordering.process_notification(second_status)
    end

    it 'buffers notifications until receives notification with id 1' do
      second_status = Follower.new(id: 2, sender: 123, recipient: 456)
      first_status  = Follower.new(id: 1, sender: 123, recipient: 789)

      expect(notification_listener).to receive(:process_notification)
        .with(first_status).ordered
      expect(notification_listener).to receive(:process_notification)
        .with(second_status).ordered

      notification_ordering.process_notification(second_status)
      notification_ordering.process_notification(first_status)
    end
  end
end

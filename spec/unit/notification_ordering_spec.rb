require 'spec_helper'

module ActivityBroker
  describe NotificationOrdering do

    let(:notification_listener) { double(process_notification: nil) }
    let(:notification_ordering) do
      NotificationOrdering.new(notification_listener, double.as_null_object)
    end

    it 'forwards notifications in order' do
      first_status  = EventNotification.new(1, 'S', 'alice')
      second_status = EventNotification.new(2, 'S', 'alice')
      third_status  = EventNotification.new(3, 'S', 'alice')
      fourth_status = EventNotification.new(4, 'S', 'alice')
      fifth_status  = EventNotification.new(5, 'S', 'alice')

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
      first_status = EventNotification.new(1, 'S', 'alice')
      second_status = EventNotification.new(2, 'S', 'alice')

      expect(notification_listener).to receive(:process_notification)
        .with(first_status).ordered
      expect(notification_listener).to receive(:process_notification)
        .with(second_status).ordered

      notification_ordering.process_notification(second_status)
      notification_ordering.process_notification(first_status)
    end
  end
end

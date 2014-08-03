require 'spec_helper'

module ActivityBroker
  describe NotificationOrdering do

    let(:notification_listener) { double(process_notification: nil) }
    let(:notification_ordering) do
      NotificationOrdering.new(notification_listener, double.as_null_object)
    end

    it 'forwards notifications in order' do
      first_status  = Broadcast.new({ id: 1, message: '1|B' }, double, double)
      second_status  = Broadcast.new({ id: 2, message: '1|B' }, double, double)
      third_status  = Broadcast.new({ id: 3, message: '1|B' }, double, double)
      fourth_status  = Broadcast.new({ id: 4, message: '1|B' }, double, double)
      fifth_status  = Broadcast.new({ id:5, message: '1|B' }, double, double)

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
      first_status  = Broadcast.new({ id: 1, message: '1|B' }, double, double)
      second_status  = Broadcast.new({ id: 2, message: '1|B' }, double, double)

      expect(notification_listener).to receive(:process_notification)
        .with(first_status).ordered
      expect(notification_listener).to receive(:process_notification)
        .with(second_status).ordered

      notification_ordering.process_notification(second_status)
      notification_ordering.process_notification(first_status)
    end
  end
end

require 'spec_helper'

module ActivityBroker
  describe NotificationDelivery do
    let!(:notification_delivery) { NotificationDelivery.new }

    it 'delivers messages to all currently registered subscribers' do
      alice_message_stream   = double
      bob_message_stream     = double
      xavier_message_stream  = double
      broadcast_notification = EventNotification.new(1, 'B', nil, '1|B')

      notification_delivery.add_subscriber('alice', alice_message_stream)
      notification_delivery.add_subscriber('bob', bob_message_stream)
      notification_delivery.add_subscriber('xavier', xavier_message_stream)

      expect(alice_message_stream).to receive(:write).with(broadcast_notification.message)
      expect(bob_message_stream).to receive(:write).with(broadcast_notification.message)
      expect(xavier_message_stream).to receive(:write).with(broadcast_notification.message)

      notification_delivery.deliver_message_to_everyone(broadcast_notification.message)
    end

    it 'delivers messages to a single registered subscriber' do
      alice_message_stream = double
      private_message_notification = EventNotification.new(1, 'P', nil, '1|P|alice|bob')

      notification_delivery.add_subscriber('alice', alice_message_stream)

      expect(alice_message_stream).to receive(:write).with(private_message_notification.message)

      notification_delivery.deliver_message_to('alice', private_message_notification.message)
    end

    it 'ignores notifications for non existent subscribers' do
      expect do
        notification_delivery.deliver_message_to('bob', '1|S|alice|bob')
      end.not_to raise_error
    end
  end
end

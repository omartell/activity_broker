require 'spec_helper'

module ActivityBroker
  describe NotificationDelivery do
    let!(:notification_delivery) { NotificationDelivery.new(logger) }
    let!(:logger) { double(:logger) }

    it 'logs subscriber id not recognized when subscriber id is not a number' do
      expect(logger).to receive(:log).with(:malformed_subscriber_id, 'alice')

      notification_delivery.add_subscriber('alice', double(:message_stream))

      expect(logger).to receive(:log).with(:malformed_subscriber_id, 'alice')

      notification_delivery.deliver_message_to('alice', 'hello!')
    end

    it 'delivers messages to all currently registered subscribers' do
      alice_message_stream   = double
      bob_message_stream     = double
      xavier_message_stream  = double
      broadcast_notification = Broadcast.new(id: 1)

      notification_delivery.add_subscriber('123', alice_message_stream)
      notification_delivery.add_subscriber('456', bob_message_stream)
      notification_delivery.add_subscriber('789', xavier_message_stream)

      expect(alice_message_stream).to receive(:write).with(broadcast_notification.message)
      expect(bob_message_stream).to receive(:write).with(broadcast_notification.message)
      expect(xavier_message_stream).to receive(:write).with(broadcast_notification.message)

      notification_delivery.deliver_message_to_everyone(broadcast_notification.message)
    end

    it 'delivers messages to a single registered subscriber' do
      alice_message_stream = double
      private_message_notification = PrivateMessage.new(id: 1, sender: '123', recipient: '456', message: '1|P|123|456')

      notification_delivery.add_subscriber('456', alice_message_stream)

      expect(alice_message_stream).to receive(:write).with(private_message_notification.message)

      notification_delivery.deliver_message_to('456', private_message_notification.message)
    end

    it 'ignores notifications for non existent subscribers' do
      expect do
        notification_delivery.deliver_message_to('999', '1|S|1|999')
      end.not_to raise_error
    end
  end
end

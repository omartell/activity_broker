require 'spec_helper'

module ActivityBroker
    describe EventSourceMessageUnpacker do
      let!(:message_unpacker) { EventSourceMessageUnpacker.new(notification_listener) }
      let!(:notification_listener) { double }

      it 'converts messages into notifications' do
        expect(notification_listener).to receive(:process_notification)
          .with(EventNotification.new(1,'F', 'alice', 'bob', '1|F|alice|bob'))

        message_unpacker.process_message('1|F|alice|bob', double)
      end
    end
end

require 'spec_helper'

module ActivityBroker
  describe EventNotification do
    it 'expects a number as the message id' do
      status_update = EventNotification.from_message('1|S|123|456')

      expect(status_update.id).to be_a Integer
    end

    it 'expects a number for sender when there is one' do
      status_update = EventNotification.from_message('1|S|123|456')

      expect(status_update.id).to be_a Integer
    end

    it 'expects a number for recipient when there is one' do
      status_update = EventNotification.from_message('1|S|123|456')

      expect(status_update.recipient).to be_a Integer
    end

    it 'is equal to another notification when the event data matches' do
      status_update_a = EventNotification.from_message('1|S|123|456')
      status_update_b = EventNotification.from_message('1|S|123|456')

      expect(status_update_a).to eq status_update_b
    end

    context 'malformed messages' do
      it 'raises an argument error when id is not a number' do
        expect do
          EventNotification.new(id: 'blah')
        end.to raise_error(ArgumentError)
      end

      it 'raises an argument error when sender is not a number' do
        expect do
          EventNotification.new(id: 1, sender: 'blah')
        end.to raise_error(ArgumentError)
      end

      it 'logs unknwon notification type errors' do
        logger = double(:logger, log: nil)

        expect(logger).to receive(:log).with(:unknown_notification_type, '1|blah|foo')

        EventNotification.from_message('1|blah|foo', logger)
      end

      it 'logs malformed message errors' do
        logger = double(:logger, log: nil)

        expect(logger).to receive(:log).with(:malformed_message, '1|F|foo|bar', 'invalid value for Integer(): "foo"')

        EventNotification.from_message('1|F|foo|bar', logger)
      end

      it 'does not log anything when there is no log' do
        expect do
          EventNotification.from_message('1|F|foo|bar')
          EventNotification.from_message('1|blah|foo')
        end.not_to raise_error
      end
    end
  end
end

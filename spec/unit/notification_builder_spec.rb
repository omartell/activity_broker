require 'spec_helper'
module ActivityBroker
  describe NotificationBuilder do
    let!(:logger) { double(:logger, log: nil) }
    let!(:builder) do
      NotificationBuilder.new(double(:postman).as_null_object,
                              double(:follower_repository).as_null_object,
                              logger.as_null_object)
    end

    it 'expects a number as the message id' do
      status_update = builder.from_message('1|S|123|456')

      expect(status_update.id).to be_a Integer
    end

    it 'expects a number for sender when there is one' do
      status_update = builder.from_message('1|S|123|456')

      expect(status_update.id).to be_a Integer
    end

    it 'expects a number for recipient when there is one' do
      status_update = builder.from_message('1|F|123|456')

      expect(status_update.recipient).to be_a Integer
    end

    it 'is equal to another notification when the event data matches' do
      status_update_a = builder.from_message('1|S|123|456')
      status_update_b = builder.from_message('1|S|123|456')

      expect(status_update_a).to eq status_update_b
    end

    context 'malformed messages' do
      it 'raises an argument error when id is not a number' do
        expect do
          StatusUpdate.new({ id: 'blah' }, double, double, double)
        end.to raise_error(ArgumentError)
      end

      it 'raises an argument error when sender is not a number' do
        expect do
          StatusUpdate.new({ id: 1, sender: 'blah'}, double, double, double)
        end.to raise_error(ArgumentError)
      end

      it 'logs unknwon notification type errors' do
        expect(logger).to receive(:log).with(:unknown_notification_type, '1|blah|foo')

        builder.from_message('1|blah|foo')
      end

      it 'logs malformed message errors' do
        expect(logger).to receive(:log)
          .with(:malformed_message, '1|F|foo|bar', 'invalid value for Integer(): "foo"')

        builder.from_message('1|F|foo|bar')
      end

      it 'does not log anything when there is no log' do
        expect do
          builder.from_message('1|F|foo|bar')
          builder.from_message('1|blah|foo')
        end.not_to raise_error
      end
    end
  end
end

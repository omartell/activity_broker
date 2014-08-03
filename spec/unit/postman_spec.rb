require 'spec_helper'

module ActivityBroker
  describe Postman do
    let!(:postman) { Postman.new(logger) }
    let!(:logger) { double(:logger).as_null_object }

    it 'logs subscriber id not recognized when subscriber id is not a number' do
      expect(logger).to receive(:log).with(:malformed_subscriber_id, 'alice')

      postman.add_subscriber('alice', double(:message_stream))

      expect(logger).to receive(:log).with(:malformed_subscriber_id, 'alice')

      postman.deliver(message: 'hello!', to: 'alice')
    end

    it 'delivers messages to a couple of subscribers' do
      alice_message_stream   = double(write: nil)
      bob_message_stream     = double(write: nil)
      xavier_message_stream  = double(write: nil)
      message = '1|S|999'

      postman.add_subscriber(123, alice_message_stream)
      postman.add_subscriber(456, bob_message_stream)
      postman.add_subscriber(789, xavier_message_stream)

      expect(alice_message_stream).to receive(:write).with(message)
      expect(bob_message_stream).to receive(:write).with(message)
      expect(xavier_message_stream).to receive(:write).with(message)

      postman.deliver(message: message, to: [123, 456, 789])
    end

    it 'delivers messages to all currently registered subscribers' do
      alice_message_stream   = double(write: nil)
      bob_message_stream     = double(write: nil)
      xavier_message_stream  = double(write: nil)
      message = '1|B'

      postman.add_subscriber(123, alice_message_stream)
      postman.add_subscriber(456, bob_message_stream)
      postman.add_subscriber(789, xavier_message_stream)

      expect(alice_message_stream).to receive(:write).with(message)
      expect(bob_message_stream).to receive(:write).with(message)
      expect(xavier_message_stream).to receive(:write).with(message)

      postman.deliver_to_all(message)
    end

    it 'delivers messages to a single registered subscriber' do
      alice_message_stream = double(write: nil)
      message = '1|P|123|456'

      postman.add_subscriber(456, alice_message_stream)

      expect(alice_message_stream).to receive(:write).with(message)

      postman.deliver(message: message, to: 456)
    end

    it 'ignores notifications for non existent subscribers' do
      expect do
        postman.deliver(message: '1|S|1|999', to: 999)
      end.not_to raise_error
    end
  end
end

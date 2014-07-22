require 'spec_helper'

module ActivityBroker
    describe MessageConverter do
    let!(:message_converter) { MessageConverter.new }

    it 'converts followed messages into followed notifications' do
      followed = message_converter.message_to_notification('1|F|123|456')

      expect(followed).to be_a Follower
    end

    it 'converts broadcast messages into broadcast notifications' do
      followed = message_converter.message_to_notification('1|B')

      expect(followed).to be_a Broadcast
    end

    it 'converts unfollowed messages into unfollowed notifications' do
      unfollowed = message_converter.message_to_notification('1|U|123|456')

      expect(unfollowed).to be_a Unfollowed
    end

    it 'converts private messages into private message notifications' do
      private_message = message_converter.message_to_notification('1|P|123|456')

      expect(private_message).to be_a PrivateMessage
    end

    it 'converts status update messages into status update notifications' do
      status_update = message_converter.message_to_notification('1|S|123|456')

      expect(status_update).to be_a StatusUpdate
    end

    it 'does not fail if it does not recognize the notification type' do
      expect do
        notification = message_converter.message_to_notification('1|BLAH|alice|bob')
      end.not_to raise_error
     end
  end
end

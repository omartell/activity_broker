require 'spec_helper'

module ActivityBroker
  describe Follower do
    let!(:postman) { double(:postman) }
    let!(:follower_repository) { double(:follower_repository, add_follower: nil) }

    it 'registers a follower' do
      alice_following_bob = Follower.new({ id: 1, sender: 123, recipient: 456, message:'1|F|123|456' },
                                         follower_repository,
                                         postman,
                                         double.as_null_object)

      expect(follower_repository).to receive(:add_follower).with(follower: 123, followed: 456)
      expect(postman).to receive(:deliver).with(message: '1|F|123|456', to: 456).once

      alice_following_bob.publish
    end
  end

  describe Unfollowed do
    let!(:postman) { double(:postman) }
    let!(:follower_repository) { double(:follower_repository, add_follower: nil) }

    it 'removes follower from recipient\'s followers' do
      unfollowed = Unfollowed.new({ id: 1, sender: 123, recipient: 456, message: '1|U|123|456' },
                                  follower_repository,
                                  postman,
                                  double.as_null_object)

      expect(follower_repository).to receive(:remove_follower).with(follower: 123, followed: 456)

      unfollowed.publish
    end
  end

  describe StatusUpdate do
    let!(:postman) { double(:postman, deliver: nil) }
    let!(:follower_repository) { double(:follower_repository, following: [1,2,3]) }

    it 'publishes status update to followers' do
      status_update = StatusUpdate.new({ id: 1, sender: 123, message: '1|S|123'},
                                       follower_repository,
                                       postman,
                                       double.as_null_object)

      expect(follower_repository).to receive(:following).with(123)
      expect(postman).to receive(:deliver).with(message: '1|S|123', to: [1,2,3])

      status_update.publish
    end
  end

  describe PrivateMessage do
    let!(:postman) { double(:postman, deliver: nil) }
    let!(:follower_repository) { double(:follower_repository, following: [1,2,3]) }

    it 'publishes private message if sender follows recipient' do
      private_message = PrivateMessage.new({ id: 1, sender: 123, recipient: 456, message: '1|P|123|456' },
                                           follower_repository,
                                           postman,
                                           double.as_null_object)

      allow(follower_repository).to receive(:is_follower?).and_return(true)

      expect(postman).to receive(:deliver).with(message: '1|P|123|456', to: 456)

      private_message.publish
    end

    it 'does not publish private message if sender doesnt follow recipient' do
      private_message = PrivateMessage.new({id: 1, nsender: 123, recipient: 456, message: '1|P|123|456'}, follower_repository, postman, double)

      allow(follower_repository).to receive(:is_follower?).and_return(false)

      expect(postman).not_to receive(:forward).with(message: '1|P|123|456', to: 456)

      private_message.publish
    end
  end

  describe Broadcast do
    let!(:postman) { double(:postman) }

    it 'publishes message to all connected subscribers' do
      broadcast = Broadcast.new({ id: 1, message: '1|B' }, postman, double)

      expect(postman).to receive(:deliver_to_all).with('1|B')

      broadcast.publish
    end
  end

end

require 'spec_helper'

module ActivityBroker
  describe FollowerRepository do

    let(:follower_repository) { FollowerRepository.new(double(:logger)) }

    it 'registers new followers' do
      follower_repository.add_follower(follower: 123, followed: 456)

      expect(follower_repository.is_follower?(follower: 123, followed: 456)).to eq true
    end

    it 'deregisters existing followers' do
      follower_repository.add_follower(follower: 123, followed: 456)
      follower_repository.remove_follower(follower: 123, followed: 456)

      expect(follower_repository.is_follower?(follower: 123, followed: 456)).to eq false
    end

    it 'knows the followers of a subscriber' do
      follower_repository.add_follower(followed: 123, follower: 456)
      follower_repository.add_follower(followed: 123, follower: 789)
      follower_repository.add_follower(followed: 123, follower: 111)

      expect(follower_repository.following(123)).to eq [456, 789, 111]
    end
  end
end

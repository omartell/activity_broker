require 'spec_helper'

module ActivityBroker
  describe IOListener do
    class FakeListener
      def forwarding_follow_event

      end
    end

    let!(:fake_listener) { FakeListener.new }
    let!(:subject) { IOListener.new(fake_listener, :forwarding_follow_event) }

    it 'is equal to other io listener when listener and event match' do
      expect(subject).to eq IOListener.new(fake_listener, :forwarding_follow_event)
    end

    it 'is not equal to another io listener when event does not match' do
      expect(subject).not_to eq IOListener.new(fake_listener, :forwarding_status_update)
    end

    it 'is not equal to anoother io listener when registered listener does not match' do
      another_fake_listener = FakeListener.new
      expect(subject).not_to eq IOListener.new(another_fake_listener, :forwarding_follow_event)
    end
  end
end

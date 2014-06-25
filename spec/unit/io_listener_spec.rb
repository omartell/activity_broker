require 'spec_helper'

module ActivityBroker
  describe IOListener do
    class FakeListener
      def forwarding_follow_event

      end
    end

    let!(:fake_listener) { FakeListener.new }
    let!(:io_listener) { IOListener.new(fake_listener, :forwarding_follow_event) }

    it 'is equal to another io listener when listener and event match' do
      expect(io_listener).to eq IOListener.new(fake_listener, :forwarding_follow_event)
    end

    it 'is not equal to another io listener when registered events dont match' do
      expect(io_listener).not_to eq IOListener.new(fake_listener, :forwarding_status_update)
    end

    it 'is not equal to another io listener when registered listeners dont match' do
      another_fake_listener = FakeListener.new
      expect(io_listener).not_to eq IOListener.new(another_fake_listener, :forwarding_follow_event)
    end
  end
end

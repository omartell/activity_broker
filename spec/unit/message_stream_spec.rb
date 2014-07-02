require 'spec_helper'
module ActivityBroker
  describe MessageStream do
    class FakeEventLoop
      def register_read(listener, event, stop_event)
        @listener = IOListener.new(listener, event, stop_event)
      end

      def notify_read_event
        @listener.notify
      end

      def notify_write_event
        @listener.notify
      end

      def register_write(listener, event, stop_event)
        @listener = IOListener.new(listener, event, stop_event)
      end

      def deregister_write(listener, event); end

      def deregister_read(listener, event); end
    end

    let!(:event_loop) { FakeEventLoop.new  }
    let!(:fake_io) { double }
    let!(:message_stream){ MessageStream.new(fake_io, event_loop, double.as_null_object) }
    let!(:message_listener) { double(:process_message) }
    let!(:one_message) { '1|U|sender|recipient' }

    it 'streams complete messages to the message listener' do
      fake_io.stub(read_nonblock: "1|U|sender|recipient" + MessageStream::MESSAGE_BOUNDARY + "2|U|sender")

      message_stream.read(message_listener)

      expect(message_listener).to receive(:process_message)
        .with(one_message, message_stream)

      event_loop.notify_read_event
    end

    it 'writes messages with the right format' do
      # Try to write 3 messages
      message_stream.write(one_message)
      message_stream.write(one_message)
      message_stream.write(one_message)

      expected_message = (one_message + MessageStream::MESSAGE_BOUNDARY) * 3

      expect(fake_io).to receive(:write_nonblock)
        .with(expected_message)
        .and_return(expected_message.bytesize / 3 * 2) # Acknowledge writing only two

      event_loop.notify_write_event

      expected_message = one_message + MessageStream::MESSAGE_BOUNDARY

      expect(fake_io).to receive(:write_nonblock)
        .with(expected_message)
        .and_return(expected_message.bytesize) # Check if we get the last message

      event_loop.notify_write_event
    end

    it 'deregisters read listener when there\'s no more data coming from the other end' do
      fake_io.stub(:read_nonblock) { raise EOFError }

      message_stream.read(message_listener)

      expect(event_loop).to receive(:deregister_read).with(message_stream, :data_received)

      event_loop.notify_read_event
    end

    it 'deregisters write listener when there\'s nothing left to write' do
      fake_io.stub(write_nonblock: (one_message + MessageStream::MESSAGE_BOUNDARY).bytesize)

      message_stream.write(one_message)

      expect(event_loop).to receive(:deregister_write).with(message_stream, :ready_to_write)

      event_loop.notify_write_event
    end
  end
end

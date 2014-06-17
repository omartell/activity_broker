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

      def deregister_write(listener, event)

      end
    end

    let!(:event_loop) { FakeEventLoop.new  }
    let!(:fake_io) { double }
    let!(:message_stream){ MessageStream.new(fake_io, event_loop, double.as_null_object) }

    it 'buffers messages from event source and streams them to the message listener' do
      fake_io.stub(read_nonblock: '1|U|sender|recipient' + MessageStream::CRLF + '2|U|sender')

      message_listener = double(:process_message)

      message_stream.read(message_listener)

      expect(message_listener).to receive(:process_message).with('1|U|sender|recipient', message_stream)

      event_loop.notify_read_event
    end

    it 'buffers outgoing messages and writes them in the right format' do
      one_message = '1|U|sender|recipient'

      # Try to write 3 messages
      message_stream.write(one_message)
      message_stream.write(one_message)
      message_stream.write(one_message)

      expected_message = (one_message + MessageStream::CRLF) * 3

      expect(fake_io).to receive(:write_nonblock)
        .with(expected_message)
        .and_return(expected_message.bytesize / 3 * 2) # Acknowledge writing only two

      event_loop.notify_write_event

      expected_message = one_message + MessageStream::CRLF

      expect(fake_io).to receive(:write_nonblock)
        .with(expected_message)
        .and_return(expected_message.bytesize) # Check if we get the last message

      event_loop.notify_write_event
    end
  end
end

require 'spec_helper'
module ActivityBroker
  describe MessageStream do
    class FakeEventLoop
      def register_read(listener, event, stop_event)
        @listener = listener
        @event = event
      end

      def notify_read_event
        @listener.send(@event)
      end
    end

    let(:event_loop) { FakeEventLoop.new  }

    it 'buffers messages from event source and streams them to the message listener' do
      io = double(read_nonblock: '1|U|sender|recipient' + MessageStream::CRLF + '2|U|sender')
      message_stream = MessageStream.new(io, event_loop, double.as_null_object)
      message_listener = double(:process_message)

      message_stream.read(message_listener)

      expect(message_listener).to receive(:process_message).with('1|U|sender|recipient', message_stream)

      event_loop.notify_read_event
    end
  end
end

module ActivityBroker
  # Wrapper class around the TCP socket object for non blocking writes and
  # reads. This class is also responsible for handling message
  # boundaries on both reads and writes. After reading a
  # complete message it tells the message listener to process the message.
  class MessageStream
    MESSAGE_BOUNDARY = "\n"
    def initialize(io, event_loop, event_logger)
      @io = io
      @event_loop = event_loop
      @event_logger = event_logger
      @read_buffer  = ''
      @write_buffer = ''
    end

    def read(message_listener)
      @message_listener = message_listener
      @event_loop.register_read(self, :data_received, :close_reading)
    end

    def write(message)
      @write_buffer << message
      @write_buffer << MESSAGE_BOUNDARY
      @event_loop.register_write(self, :ready_to_write, :close_writting)
    end

    def to_io
      @io
    end

    private

    def close_writing
      @io.close_write
    end

    def close_reading
      @io.close_read
    end

    def ready_to_write
      begin
        written_so_far = @io.write_nonblock(@write_buffer)
        @write_buffer.slice!(0, written_so_far)
        if @write_buffer.empty?
          @event_loop.deregister_write(self, :ready_to_write)
        end
      rescue Errno::EAGAIN
        # write would actually block
      end
    end

    def data_received
      begin
        @read_buffer << @io.read_nonblock(4096)
        stream_messages
      rescue IO::WaitReadable
        # IO isn't actually readable.
      rescue EOFError
        # No more data coming from the other end
        @event_loop.deregister_read(self, :data_received)
      end
    end

    def stream_messages
      message_regex = /([^\n]*)\n/
      @read_buffer.scan(message_regex).flatten.each do |m|
        @event_logger.log(:streaming_message, m)
        @message_listener.process_message(m, self)
      end
      @read_buffer = @read_buffer.gsub(message_regex, '')
    end
  end
end

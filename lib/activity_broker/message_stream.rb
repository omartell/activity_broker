module ActivityBroker
  # Wrapper class around the TCP socket object for non blocking writes and
  # reads. This class is also responsible for handling message
  # boundaries on both reads and writes. After reading a
  # complete message it tells the message listener to process the message.
  class MessageStream
    MESSAGE_BOUNDARY = "\n"
    READ_SIZE = 4096 # bytes
    MESSAGE_REGEX = /([^\n]*)\n/

    def initialize(io, event_loop, event_logger)
      @io = io
      @event_loop = event_loop
      @event_logger = event_logger
      @read_buffer  = ''
      @write_buffer = ''
    end

    def on_message_received(&message_received_handler)
      @message_received_handler = message_received_handler
      @event_loop.register_read(self, :ready_to_read, :close_reading)
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
      written_so_far = @io.write_nonblock(@write_buffer)
      @write_buffer.slice!(0, written_so_far)
      if @write_buffer.empty?
        @event_loop.deregister_write(self, :ready_to_write)
      end
    rescue Errno::EAGAIN
        # write would actually block
    end

    def ready_to_read
      @read_buffer << @io.read_nonblock(READ_SIZE)
      stream_messages
    rescue IO::WaitReadable
      # IO isn't actually readable.
    rescue EOFError, Errno::ECONNRESET
      # No more data coming from the other end
      @event_loop.deregister_read(self, :ready_to_read)
    end

    def stream_messages
      @read_buffer.scan(MESSAGE_REGEX).flatten.each do |message|
        @event_logger.log(:streaming_message, message)
        @message_received_handler.call(message, self)
      end
      @read_buffer = @read_buffer.gsub(MESSAGE_REGEX, '')
    end
  end
end

module ActivityBroker
  class MessageStream
    CRLF = '/r/n'
    def initialize(io, event_loop, event_logger)
      @io = io
      @event_loop = event_loop
      @event_logger = event_logger
      @read_buffer  = ''
      @write_buffer = ''
    end

    def read(message_listener)
      @message_listener = message_listener
      @event_loop.register_read(self, :data_received)
    end

    def to_io
      @io
    end

    def write(message)
      @write_buffer << message
      @write_buffer << CRLF
      @event_loop.register_write(self, :ready_to_write)
    end

    def close
      return if @closed
      @event_loop.deregister_write(self, :ready_to_write)
      @event_loop.deregister_read(self, :data_received)
      @io.close
      @closed = true
    end

  private

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
        # do we really need to have closed guard?
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
      message_regex = /([^\/]*)\/r\/n/
      @read_buffer.scan(message_regex).flatten.each do |m|
        @event_logger.log(:streaming_message, m)
        @message_listener.process_message(m, self)
      end
      @read_buffer = @read_buffer.gsub(message_regex, '')
    end
  end
end

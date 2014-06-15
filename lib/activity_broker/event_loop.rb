module ActivityBroker
  class EventLoop
    def initialize(event_logger)
      @reading = []
      @writing = []
      @event_logger  = event_logger
    end

    def start
      loop do
        if @stop
          @event_logger.log(:stopping_event_loop)
          break
        end

        ready_reading, ready_writing, _ = IO.select(@reading, @writing, nil, 0)
        ready_reading.each(&:notify) if ready_reading
        ready_writing.each(&:notify) if ready_writing
      end
    end

    def register_read(listener, read_event)
      register_on(@reading, listener, read_event)
    end

    def register_write(listener, write_event)
      register_on(@writing, listener, write_event)
    end

    def stop
      @stop = true
    end

    def deregister_write(listener, event)
      @writing.delete(new_io_listener(listener, event))
    end

    def deregister_read(listener, event)
      @reading.delete(new_io_listener(listener, event))
    end

    private

    def register_on(io_listeners, listener, event)
      io_listener = new_io_listener(listener, event)
      if !io_listeners.include?(io_listener)
        io_listeners << io_listener
      end
    end

    def new_io_listener(listener, event)
      IOListener.new(listener, event)
    end
  end
end

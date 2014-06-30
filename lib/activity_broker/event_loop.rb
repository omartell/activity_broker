module ActivityBroker
  # The Event Loop is the main control flow construct in the
  # application. Listener objects can register read/write interest
  # on IO objects. The event loop is in charge of notifying the listener
  # objects when their registered IO object is ready to be read from
  # or written to. Internally this class uses ruby's IO select to
  # allow for non-blocking program execution.
  class EventLoop
    def initialize(event_logger)
      @reading = []
      @writing = []
      @event_logger = event_logger
    end

    def start
      loop do
        if @stop
          @writing.each(&:on_event_loop_stop)
          @reading.each(&:on_event_loop_stop)
          @event_logger.log(:stopping_event_loop)
          break
        end

        ready_reading, ready_writing, _ = IO.select(@reading, @writing, nil, 0)
        ready_reading.each(&:notify) if ready_reading
        ready_writing.each(&:notify) if ready_writing
      end
    end

    def register_read(listener, read_event, stop_event)
      register_on(@reading, listener, read_event, stop_event)
    end

    def register_write(listener, write_event, stop_event)
      register_on(@writing, listener, write_event, stop_event)
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

    def register_on(io_listeners, listener, event, stop_event)
      io_listener = new_io_listener(listener, event, stop_event)
      if !io_listeners.include?(io_listener)
        io_listeners << io_listener
      end
    end

    def new_io_listener(listener, event, stop_event = nil)
      IOListener.new(listener, event, stop_event)
    end
  end
end

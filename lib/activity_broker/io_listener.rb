module ActivityBroker
  # This class is mainly used to group the listener object that
  # registered interest on the IO object, the event to be triggered when
  # the IO object is ready for read/write and the stop event dispached
  # when the application is about to shutdown.
  class IOListener
    attr_reader :listener, :io_event
    def initialize(listener, io_event, stop_event = nil)
      @listener = listener
      @io_event = io_event
      @stop_event = stop_event
    end

    def to_io
      @listener.to_io
    end

    def ==(other_io_listener)
      io_event == other_io_listener.io_event &&
      listener == other_io_listener.listener
    end

    def on_event_loop_stop
      @listener.send(@stop_event)
    end

    def notify
      @listener.send(@io_event)
    end
  end
end

module ActivityBroker
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

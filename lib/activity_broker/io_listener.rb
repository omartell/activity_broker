module ActivityBroker
  class IOListener
    attr_reader :listener, :event
    def initialize(listener, event)
      @listener = listener
      @event    = event
    end

    def to_io
      @listener.to_io
    end

    def ==(other_io_listener)
      self.event == other_io_listener.event &&
      self.listener == other_io_listener.listener
    end

    def notify
      @listener.send(@event)
    end
  end
end

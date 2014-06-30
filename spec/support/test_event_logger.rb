class TestEventLogger < ActivityBroker::ApplicationEventLogger
  # This class delegates logging to the parent Application Event Logger and
  # it's also used in integration tests to collect application events,
  # wait for a certain event to synchronize the tests and assert that a certain action
  # has happened in the application.
  def initialize(output, level = Logger::DEBUG)
    @events = []
    super(output, level)
  end

  def has_received_event?(event, *other)
    event_data = [event] + other
    @events.include?(event_data)
  end

  def log(event, *other)
    @events << ([event] + other)
    super(event, *other)
  end

  def publishing_event(message)
    log_debug('publishing event: ' + message)
  end

  def sending_subscriber_id(subscriber_id)
    log_debug('sending subscriber id: ' + subscriber_id)
  end

  def receiving_notification(notification, subscriber_id)
    log_debug(subscriber_id + ' received notification: ' + notification)
  end

  def stopping_event_source(port)
    log_debug('stopping event source on port ' + port.to_s)
  end

  def stopping_subscriber(client_id, port)
    log_debug('stopping subscriber ' + client_id + ' on port ' + port.to_s )
  end
end

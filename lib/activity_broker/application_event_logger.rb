require 'logger'
module ActivityBroker
  # The Application Event Logger receives application events forwarded by
  # all the application components and decides if those
  # events should be logged and how they should be logged.
  # This class was used for debugging purposes and integration testing.
  class ApplicationEventLogger
    def initialize(output, level)
      @logger = Logger.new(output)
      @logger.datetime_format = "%Y-%m-%d %H:%M:%S"
      @logger.level = level
    end

    def log(event, *other)
      send(event, *other)
    end

    private

    def log_debug(message)
      @logger.debug(message)
    end

    def log_info(message)
      @logger.info(message)
    end

    def starting_activity_broker
      log_info('=======================================================')
      log_info('Starting Activity Broker')
    end

    def server_accepting_connections(port)
      log_info('TCP Server accepting connections on port ' + port.to_s)
    end

    def connection_accepted(port)
      log_debug('connection accepted on port ' + port.to_s)
    end

    def streaming_message(message)
      log_debug('streaming message ' + message)
    end

    def registering_subscriber(subscriber_id)
      puts 'REGISTEING'
      log_debug('registering subscriber ' + subscriber_id)
    end

    def discarding_unfollow_event(message)
      log_debug('discarding unfollow event: ' + message)
    end

    def forwarding_broadcast_event(notification)
      log_debug('forwarding broadcast event: ' + notification.message)
    end

    def forwarding_follow_event(notification)
      log_debug('forwarding follow event: ' + notification.message)
    end

    def forwarding_unfollow_event(notification)
      log_debug('forwarding unfollow event: ' + notification.message)
    end

    def forwarding_status_update(notification)
      log_debug('forwarding status update: ' + notification.message)
    end

    def forwarding_private_message(notification)
      log_debug('forwarding private message: ' + notification.message)
    end

    def stopping_server(port)
      log_debug('stopping server on port ' + port.to_s)
    end

    def stopping_event_loop
      log_info('stopping activity broker')
    end
  end
end

module ActivityBroker
  # This is the application starting point. The class takes
  # the event source port, subscriber port and an application event
  # logger as configuration parameters, bootstraps all the components
  # and starts accepting TCP connections from the event source and
  # subscribers. Then the runner kicks off the notification processing by
  # starting the main IO event loop.

  class NotificationPublisher
    def process_notification(notification)
      notification.publish
    end
  end

  class ApplicationRunner

    def initialize(config)
      @config = config
      @event_logger = @config.fetch(:event_logger) do
        ApplicationEventLogger.new(STDOUT, Logger::INFO)
      end
      @event_loop = EventLoop.new(@event_logger)
    end

    def start
      event_source_server = Server.new(@config.fetch(:event_source_port), @event_loop, @event_logger)
      subscriber_server   = Server.new(@config.fetch(:subscriber_port), @event_loop, @event_logger)
      postman = Postman.new(@event_logger)
      follower_repository = FollowerRepository.new(@event_logger)
      notification_ordering   = NotificationOrdering.new(NotificationPublisher.new, @event_logger)
      notification_builder = NotificationBuilder.new(postman, follower_repository, @event_logger)

      @event_logger.log(:starting_activity_broker)

      event_source_server.on_connection_accepted do |connection|
        message_stream = MessageStream.new(connection, @event_loop, @event_logger)
        message_stream.on_message_received do |message, message_stream|
          notification = notification_builder.from_message(message)
          notification_ordering.process_notification(notification)
        end
      end

      subscriber_server.on_connection_accepted do |connection|
        message_stream = MessageStream.new(connection, @event_loop, @event_logger)
        message_stream.on_message_received do |subscriber_id, message_stream|
          postman.add_subscriber(subscriber_id, message_stream)
        end
      end

      @event_loop.start
    end

    def stop
      @event_loop.stop
    end
  end
end

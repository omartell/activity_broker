module ActivityBroker
  # This is the application starting point. The class takes
  # the event source port, subscriber port and an application event
  # logger as configuration parameters, bootstraps all the components
  # and starts accepting TCP connections from the event source and
  # subscribers. Then the runner kicks off the notification processing by
  # starting the main IO event loop.
  class ApplicationRunner
    def initialize(config)
      @config = config
      @event_logger = @config.fetch(:event_logger) { ApplicationEventLogger.new(STDOUT, Logger::INFO) }
      @event_loop = EventLoop.new(@event_logger)
    end

    def start
      event_source_server = start_server_on(:event_source_port)
      subscriber_server   = start_server_on(:subscriber_port)
      notification_router     = NotificationRouter.new(NotificationDelivery.new, @event_logger)
      notification_translator = NotificationTranslator.new(notification_router)
      notification_ordering   = NotificationOrdering.new(notification_translator, @event_logger)
      message_unpacker        = EventSourceMessageUnpacker.new(notification_ordering)
      subscriber_translator = SubscriberMessageTranslator.new(notification_router)

      @event_logger.log(:starting_activity_broker)

      event_source_server.on_connection_accepted do |connection|
        message_stream = MessageStream.new(connection, @event_loop, @event_logger)
        message_stream.on_message_received do |message, message_stram|
          message_unpacker.process_message(message, message_stream)
        end
      end

      subscriber_server.on_connection_accepted do |connection|
        message_stream = MessageStream.new(connection, @event_loop, @event_logger)
        message_stream.on_message_received do |message, message_stream|
          subscriber_translator.process_message(message, message_stream)
        end
      end

      @event_loop.start
    end

    def stop
      @event_loop.stop
    end

    private

    def start_server_on(port)
      Server.new(@config.fetch(port), @event_loop, @event_logger)
    end
  end
end

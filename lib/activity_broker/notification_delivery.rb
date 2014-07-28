module ActivityBroker
  # This class is in charge of delivering a message to a specific
  # subscriber.
  class NotificationDelivery
    def initialize(logger)
      @subscribers = {}
      @logger = logger
    end

    def add_subscriber(subscriber_id, subscriber_stream)
      @subscribers[Integer(subscriber_id)] = subscriber_stream
    rescue ArgumentError => error
      @logger.log(:malformed_subscriber_id, subscriber_id)
    end

    def deliver_message_to(subscriber_id, message)
      subscriber_stream = @subscribers[Integer(subscriber_id)]
      if subscriber_stream
        subscriber_stream.write(message)
      end
    rescue ArgumentError => error
      @logger.log(:malformed_subscriber_id, subscriber_id)
    end

    def deliver_message_to_everyone(message)
      @subscribers.each do |subscriber_id, subscriber_stream|
        subscriber_stream.write(message)
      end
    end

  end
end

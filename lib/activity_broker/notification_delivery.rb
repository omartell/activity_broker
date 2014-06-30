module ActivityBroker
  # This class is in charge of delivering a message to a specific
  # subscriber.
  class NotificationDelivery
    def initialize
      @subscribers = {}
    end

    def add_subscriber(subscriber_id, subscriber_stream)
      @subscribers[subscriber_id] = subscriber_stream
    end

    def deliver_message_to(recipient, message)
      if subscriber_stream = @subscribers[recipient]
        subscriber_stream.write(message)
      end
    end

    def deliver_message_to_everyone(message)
      @subscribers.each do |subscriber_id, subscriber_stream|
        subscriber_stream.write(message)
      end
    end
  end
end

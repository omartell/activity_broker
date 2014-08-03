module ActivityBroker
  # This class is in charge of delivering a message to a specific
  # subscriber.
  class Postman
    def initialize(logger)
      @subscribers = {}
      @logger = logger
    end

    def add_subscriber(subscriber_id, subscriber_stream)
      @subscribers[Integer(subscriber_id)] = subscriber_stream
      @logger.log(:registering_subscriber, subscriber_id)
    rescue ArgumentError => error
      @logger.log(:malformed_subscriber_id, subscriber_id)
    end

    def deliver(message: , to:)
      Array(to).map do |recipient|
        @subscribers[Integer(recipient)]
      end.compact.each do |subscriber_stream|
        subscriber_stream.write(message)
      end
    rescue ArgumentError => error
      @logger.log(:malformed_subscriber_id, to)
    end

    def deliver_to_all(message)
      @subscribers.each do |subscriber_id, subscriber_stream|
        subscriber_stream.write(message)
      end
    end

  end
end

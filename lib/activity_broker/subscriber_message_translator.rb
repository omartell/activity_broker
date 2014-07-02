module ActivityBroker
  # This class knows that the only message coming from a subscriber is
  # the subscription message. So, when a message arrives it tells the
  # translated message listener to register the subscriber.
  class SubscriberMessageTranslator
    def initialize(translated_message_listener)
      @translated_message_listener = translated_message_listener
    end

    def process_message(message, subscriber_stream)
      @translated_message_listener.register_subscriber(message, subscriber_stream)
    end
  end
end

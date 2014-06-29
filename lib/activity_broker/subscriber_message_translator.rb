module ActivityBroker
  class SubscriberMessageTranslator
    def initialize(translated_message_listener)
      @translated_message_listener = translated_message_listener
    end

    def process_message(message, subscriber_stream)
      @translated_message_listener.register_subscriber(message, subscriber_stream)
    end
  end
end

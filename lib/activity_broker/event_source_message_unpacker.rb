module ActivityBroker
  class EventSourceMessageUnpacker
    # This class is in charge of converting the messages from the
    # message stream into event notifications, which are
    # forwarded to the notification listener.
    def initialize(notification_listener)
      @notification_listener = notification_listener
    end

    def process_message(message, message_stream)
      id, type, sender, recipient = message.split('|')
      notification = EventNotification.new(id.to_i, type, sender, recipient, message)
      @notification_listener.process_notification(notification)
    end
  end
end

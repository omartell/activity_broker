module ActivityBroker
  class NotificationTranslator
    def initialize(notification_listener)
      @notification_listener = notification_listener
    end

    def process_notification(notification)
      case notification.type
      when 'B'
        @notification_listener.process_broadcast_event(notification)
      when 'F'
        @notification_listener.process_follow_event(notification)
      when 'U'
        @notification_listener.process_unfollow_event(notification)
      when 'P'
        @notification_listener.process_private_message_event(notification)
      when 'S'
        @notification_listener.process_status_update_event(notification)
      end
    end
  end
end

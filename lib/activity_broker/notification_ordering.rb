module ActivityBroker
  class NotificationOrdering
    # This class enqueues notifications and then forwards them in order
    # to the notification listener. The notifications are ordered
    # by id - the first notification starts with id 1.
    def initialize(notification_listener, event_logger)
      @notification_listener = notification_listener
      @last_notification = nil
      @notification_queue = {}
      @event_logger = event_logger
    end

    def process_notification(current_notification)
      if is_this_the_next_notification?(current_notification)
        forward_notification(current_notification)
        process_queued_notifications
      else
        queue_notification(current_notification)
      end
    end

    private

    def queue_notification(notification)
      @notification_queue[notification.id] = notification
    end

    def process_queued_notifications
      notification = @notification_queue[@last_notification.id + 1]
      if notification
        forward_notification(notification)
        process_queued_notifications
      end
    end

    def forward_notification(notification)
      @event_logger.send(:log_info, 'forwarding notification ' + notification.message)
      @notification_listener.process_notification(notification)
      @last_notification = notification
      @notification_queue.delete(notification.id)
    end

    def is_this_the_next_notification?(next_notification)
      if @last_notification.nil?
        next_notification.id == 1
      else
        next_notification.id - @last_notification.id == 1
      end
    end
  end
end

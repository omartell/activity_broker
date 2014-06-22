module ActivityBroker
  class NotificationOrdering
    def initialize(next_notification_listener, event_logger)
      @next_notification_listener = next_notification_listener
      @last_notification = nil
      @notification_queue = []
      @event_logger = event_logger
    end

    def process_notification(current_notification)
      if is_this_the_next_notification?(current_notification)
        forward_notification(current_notification)
        @notification_queue.sort! { |x, y| x.id <=> y.id }
        process_queued_notifications
      else
        @notification_queue << current_notification
      end
    end

    private

    def process_queued_notifications
      notification = @notification_queue.shift
      if notification && is_this_the_next_notification?(notification)
        forward_notification(notification)
        process_queued_notifications
      elsif notification
        @notification_queue.unshift(notification)
      end
    end

    def forward_notification(notification)
      @next_notification_listener.process_notification(notification)
      @last_notification = notification
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

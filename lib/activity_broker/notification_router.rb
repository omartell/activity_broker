module ActivityBroker
  class NotificationRouter
    def initialize(notification_delivery, event_logger)
      @followers = Hash.new { |hash, key| hash[key] = [] }
      @delivery  = notification_delivery
      @event_logger = event_logger
    end

    def register_subscriber(subscriber_id, subscriber_stream)
      @delivery.add_subscriber(subscriber_id, subscriber_stream)
      log(:registering_subscriber, subscriber_id)
    end

    def process_broadcast_event(notification)
      @delivery.deliver_message_to_everyone(notification.message)
      log(:forwarding_broadcast_event, notification)
    end

    def process_follow_event(notification)
      add_follower(notification.sender, notification.recipient)
      @delivery.deliver_message_to(notification.recipient, notification.message)
      log(:forwarding_follow_event, notification)
    end

    def process_unfollow_event(notification)
      remove_follower(notification.sender, notification.recipient)
      log(:discarding_unfollow_event, notification.message)
    end

    def process_status_update_event(notification)
      @followers[notification.sender].each do |follower|
        @delivery.deliver_message_to(follower, notification.message)
      end
      log(:forwarding_status_update, notification)
    end

    def process_private_message_event(notification)
      @delivery.deliver_message_to(notification.recipient, notification.message)
      log(:forwarding_private_message, notification)
    end

    private

    def log(event, notification)
      @event_logger.log(event, notification)
    end

    def remove_follower(follower, followed)
      @followers[followed] = @followers[followed] - [follower]
    end

    def add_follower(follower, followed)
      @followers[followed] << follower
    end
  end
end
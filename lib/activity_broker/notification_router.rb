require 'set'
module ActivityBroker
  class NotificationRouter
    # The notification router is in charge of forwarding the
    # notifications to the appropriate subscribers based on the
    # notification received. It also keeps track of the current
    # subscribers followers and uses an instance of
    # NotificationDelivery to write the messages to the subscribers.
    def initialize(notification_delivery, event_logger)
      @followers = Hash.new { |hash, key| hash[key] = Set.new }
      @delivery  = notification_delivery
      @event_logger = event_logger
    end

    def register_subscriber(subscriber_id, subscriber_stream)
      @delivery.add_subscriber(subscriber_id, subscriber_stream)
      log(:registering_subscriber, subscriber_id)
      puts 'adding subscriber' + Integer(subscriber_id).inspect
    end

    def process_broadcast_event(notification)
      @delivery.deliver_message_to_everyone(notification.message)
      log(:forwarding_broadcast_event, notification)
    end

    def process_follow_event(notification)
      follower = notification.sender
      followed = notification.recipient
      if new_follower?(follower, followed)
        add_follower(follower, followed)
        @delivery.deliver_message_to(followed, notification.message)
        log(:forwarding_follow_event, notification)
      end
    end

    def process_unfollow_event(notification)
      follower = notification.sender
      followed = notification.recipient
      remove_follower(follower, followed)
      log(:discarding_unfollow_event, notification.message)
    end

    def process_status_update_event(notification)
      followed = notification.sender
      @followers[followed].each do |follower|
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

    def new_follower?(follower, followed)
      !@followers[followed].member?(follower)
    end

    def remove_follower(follower, followed)
      @followers[followed] = @followers[followed] - [follower]
    end

    def add_follower(follower, followed)
      @followers[followed] << follower
    end
  end
end

module ActivityBroker
  class EventNotification
    attr_reader :id, :sender, :recipient, :message, :type

    def initialize_id
      @id = validate_numerical(@event[:id])
    end

    def initialize_sender
      @sender = validate_numerical(@event[:sender])
    end

    def initialize_recipient
      @recipient = validate_numerical(@event[:recipient])
    end

    def initialize_message
      @message = validate_presence(@event[:message], :message)
    end

    def validate_presence(arg, argument_name)
      if arg.nil? || arg.to_s.empty?
        raise ArgumentError.new("#{argument_name.to_s} is required")
      else
        arg
      end
    end

    def validate_numerical(number)
      if !number.nil?
        Integer(number)
      end
    end

    def ==(other_notification)
      id == other_notification.id &&
      sender == other_notification.sender &&
      recipient == other_notification.recipient &&
      type == other_notification.type &&
      message == other_notification.message
    end
  end

  class Follower < EventNotification
    def initialize(event, follower_repository, postman, logger)
      @event = event
      @postman = postman
      @follower_repository = follower_repository
      @logger = logger
      initialize_id
      initialize_sender
      initialize_recipient
      initialize_message
    end

    def publish
      @follower_repository.add_follower(follower: sender, followed: recipient)
      @postman.deliver(message: message, to: recipient)
    end
  end

  class Unfollowed < EventNotification
    def initialize(event, follower_repository, postman, logger)
      @event = event
      @follower_repository = follower_repository
      @postman = postman
      @logger = logger
      initialize_id
      initialize_sender
      initialize_recipient
      initialize_message
    end

    def publish
      @logger.log(:discarding_unfollow_event, message)
      @follower_repository.remove_follower(follower: sender, followed: recipient)
    end
  end

  class StatusUpdate < EventNotification
    def initialize(event, follower_repository, postman, logger)
      @event = event
      @follower_repository = follower_repository
      @postman = postman
      @logger  = logger
      initialize_id
      initialize_sender
      initialize_message
    end

    def publish
      followers = @follower_repository.following(sender)
      @logger.send(:log_info, 'sending status update: ' + followers.inspect)
      @postman.deliver(message: @event[:message], to: followers)
    end
  end

  class PrivateMessage < EventNotification
    def initialize(event, follower_repository, postman, logger)
      @event = event
      @follower_repository = follower_repository
      @postman = postman
      @logger = logger
      initialize_id
      initialize_sender
      initialize_recipient
      initialize_message
    end

    def publish
      if @follower_repository.is_follower?(follower: sender, followed: recipient)
        @postman.deliver(message: message, to: recipient)
      end
    end
  end

  class Broadcast < EventNotification
    def initialize(event, postman, logger)
      @event = event
      @postman = postman
      @logger = logger
      initialize_id
      initialize_message
    end

    def publish
      @postman.deliver_to_all(message)
    end
  end
end

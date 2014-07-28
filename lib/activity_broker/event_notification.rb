module ActivityBroker
  class EventNotification

    MESSAGE_TYPES_TO_NOTIFICATIONS = {
      'F' => -> (event) { Follower.new(event) },
      'U' => -> (event) { Unfollowed.new(event) },
      'S' => -> (event) { StatusUpdate.new(event) },
      'P' => -> (event) { PrivateMessage.new(event) },
      'B' => -> (event) { Broadcast.new(event) }
    }

    attr_reader :id, :sender, :recipient, :message, :type

    def self.from_message(message, logger = nil)
      id, type, sender, recipient = message.split('|')
      notification = MESSAGE_TYPES_TO_NOTIFICATIONS[type]

      if notification
        event = { id: id, sender: sender, recipient: recipient, message: message }
        notification.call(event)
      else
        logger.log(:unknown_notification_type, message) if logger
        nil
      end
    rescue ArgumentError => error
      logger.log(:malformed_message, message, error.message) if logger
      nil
    end

    def initialize(event_data)
      @id     = validate_numerical(event_data[:id])
      @sender = validate_numerical(event_data[:sender])
      @recipient = validate_numerical(event_data[:recipient])
      @type      = event_data[:type]
      @message   = event_data[:message]
    end

    def to_s
      message
    end

    def validate_numerical(number)
      if !number.nil?
        Integer(number)
      end
    end

    def validate_presence(arg, argument_name)
      if arg.nil? || arg.to_s.empty?
        raise ArgumentError.new("#{argument_name.to_s} is required")
      else
        arg
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
    def initialize(*args)
      super
      validate_presence(sender, :follower)
      validate_presence(recipient, :followed)
    end
  end

  class Unfollowed < EventNotification
    def initialize(*args)
      super
      validate_presence(sender, :follower)
      validate_presence(recipient, :followed)
    end
  end

  class StatusUpdate < EventNotification
    def initialize(*args)
      super
      validate_presence(sender, :followed)
    end
  end

  class PrivateMessage < EventNotification
    def initialize(*args)
      super
      validate_presence(sender, :sender)
      validate_presence(recipient, :recipient)
    end
  end

  class Broadcast < EventNotification

  end
end

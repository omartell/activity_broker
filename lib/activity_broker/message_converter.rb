module ActivityBroker
  class MessageConverter

    MESSAGE_TYPES_TO_NOTIFICATIONS = {
      'F' => Follower,
      'U' => Unfollowed,
      'S' => StatusUpdate,
      'P' => PrivateMessage,
      'B' => Broadcast
    }

    # This class is in charge of converting the messages from the
    # message stream into event notifications.
    def message_to_notification(message)
      id, current_type, sender, recipient = message.split('|')

      klass = MESSAGE_TYPES_TO_NOTIFICATIONS[current_type]

      if klass
        klass.new(id.to_i, current_type, sender, recipient, message)
      end
    end
  end
end

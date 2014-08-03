module ActivityBroker
  class NotificationBuilder
    MESSAGE_TYPES_TO_NOTIFICATIONS = {
      'F' => -> (args) {
        Follower.new(args[:event],
                     args[:follower_repository],
                     args[:postman],
                     args[:logger])
      },
      'U' => -> (args) {
        Unfollowed.new(args[:event],
                       args[:follower_repository],
                       args[:postman],
                       args[:logger])
      },
      'S' => -> (args) {
        StatusUpdate.new(args[:event],
                         args[:follower_repository],
                         args[:postman],
                         args[:logger])
      },
      'P' => -> (args) {
        PrivateMessage.new(args[:event],
                           args[:follower_repository],
                           args[:postman],
                           args[:logger])
      },
      'B' => -> (args) {
        Broadcast.new(args[:event],
                      args[:postman],
                      args[:logger])
      }
    }

    def initialize(postman, follower_repository, logger)
      @postman = postman
      @follower_repository = follower_repository
      @logger = logger
    end

    def from_message(message)
      event = event_from_message(message)
      notification = MESSAGE_TYPES_TO_NOTIFICATIONS[event[:type]]

      if notification
        notification.call(event: event, postman: @postman, logger: @logger,
                          follower_repository: @follower_repository)
      else
        @logger.log(:unknown_notification_type, message)
        nil
      end
    rescue ArgumentError => error
      @logger.log(:malformed_message, message, error.message)
      nil
    end

    private

    def event_from_message(message)
      id, type, sender, recipient = message.split('|')
      { id: id,
        type: type,
        sender: sender,
        recipient: recipient,
        message: message }
    end
  end
end

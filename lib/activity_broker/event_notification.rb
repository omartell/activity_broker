module ActivityBroker
  EventNotification = Struct.new(:id, :type, :sender, :recipient, :message)

  class Follower < EventNotification

  end

  class Unfollowed < EventNotification

  end

  class StatusUpdate < EventNotification

  end

  class PrivateMessage < EventNotification

  end

  class Broadcast < EventNotification

  end
end

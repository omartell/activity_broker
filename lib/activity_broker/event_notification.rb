module ActivityBroker
  EventNotification = Struct.new(:id, :type, :sender, :recipient, :message)
end

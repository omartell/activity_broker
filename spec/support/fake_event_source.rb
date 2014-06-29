class FakeEventSource
  def initialize(host, port, event_logger)
    @host = host
    @port = port
    @event_id = 0
    @event_logger = event_logger
  end

  def start
    @connection = TCPSocket.new(@host, @port)
  end

  def publish_broadcast_event(options = {})
    publish_event('B', options[:id])
  end

  def publish_new_follower_to(recipient, sender, options = {})
    publish_event('F', sender, recipient, options[:id])
  end

  def publish_status_update_from(sender, options = {})
    publish_event('S', sender, options[:id])
  end

  def publish_private_message_to(recipient, sender, options = {})
    publish_event('P', sender, recipient, options[:id])
  end

  def publish_unfollow_to(recipient, sender, options = {})
    publish_event('U', sender, recipient, options[:id])
  end

  def stop
    @event_logger.log(:stopping_event_source, @port)
    @connection.close
  end

  private

  def publish_event(*notification_args, id)
    notification_args.unshift(id || generate_event_id)
    full_message = notification_args.join('|')
    @event_logger.log(:publishing_event, full_message)
    @connection.write(full_message)
    @connection.write(ActivityBroker::MessageStream::MESSAGE_BOUNDARY)
    full_message
  end

  def generate_event_id
    @event_id += 1
  end
end

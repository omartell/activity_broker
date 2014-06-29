class FakeSubscriber
  def initialize(client_id, address, port, event_logger)
    @client_id = client_id
    @address = address
    @port = port
    @event_logger = event_logger
    @notifications = []
  end

  def start
    begin
      @connection = TCPSocket.new(@address, @port)
    rescue Errno::ECONNREFUSED
      retry
    end
  end

  def closed?
    @connection.closed?
  end

  def send_client_id
    @connection.write(@client_id)
    @connection.write(ActivityBroker::MessageStream::MESSAGE_BOUNDARY)
    @event_logger.log(:sending_subscriber_id, @client_id)
  end

  def has_received_notification_of?(notification)
    if @notifications.include?(notification.to_s)
      true
    else
      read_notifications
      false
    end
  end

  def stop
    @event_logger.log(:stopping_subscriber, @client_id, @port)
    @connection.close
  end

  private

  def read_notifications
    read_ready, _, _ = IO.select([@connection], nil, nil, 0)
    if read_ready
      begin
        buffer = read_ready.first.read_nonblock(4096)
        buffer.split(ActivityBroker::MessageStream::MESSAGE_BOUNDARY).each do |notification|
          @event_logger.log(:receiving_notification, notification, @client_id)
          @notifications << notification
        end
      rescue EOFError
        # broker closed connection
      end
    end
  end
end

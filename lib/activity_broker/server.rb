require 'socket'
module ActivityBroker
  # This class registers itself with the Event Loop to read from the TCP Server
  # instance. The event loop will then notify when a new
  # connection is ready to be accepted. After the server accepts the
  # connection it will call the listener block with an instance of MessageStream.
  class Server
    def initialize(port, event_loop, event_logger)
      @port = port
      @event_loop = event_loop
      @event_logger = event_logger
      @message_streams = []
    end

    def accept_connections(&connection_accepted_listener)
      @event_logger.log(:server_accepting_connections, @port)
      @tcp_server = TCPServer.new(@port)
      @connection_accepted_listener = connection_accepted_listener
      @event_loop.register_read(self, :process_new_connection, :close_server)
    end

    def to_io
      @tcp_server
    end

    private

    def close_server
      @tcp_server.close
    end

    def process_new_connection
      connection     = @tcp_server.accept_nonblock
      message_stream = MessageStream.new(connection, @event_loop, @event_logger)

      @connection_accepted_listener.call(message_stream)
      @event_logger.log(:connection_accepted, @port)
    end
  end
end

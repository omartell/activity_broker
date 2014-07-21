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
    end

    def on_connection_accepted(&connection_accepted_handler)
      @event_logger.log(:server_accepting_connections, @port)
      @tcp_server = TCPServer.new(@port)
      @connection_accepted_handler = connection_accepted_handler
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
      connection = @tcp_server.accept_nonblock
      @connection_accepted_handler.call(connection)
      @event_logger.log(:connection_accepted, @port)
    end
  end
end

require 'socket'
module ActivityBroker
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

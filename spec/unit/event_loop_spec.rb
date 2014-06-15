require 'spec_helper'
require 'support/async_helper'
require 'socket'

module ActivityBroker
  describe EventLoop do
    include AsyncHelper

    class FakeIO
      def initialize(io)
        @io = io
      end

      def to_io
        @io
      end

      def read_ready_connection
        @read_ready_connection = true
      end

      def close
        @io.close
      end

      def reset
        @read_ready_connection = false
        @write_ready_connection = false
      end

      def has_received_read_ready_connection?
        @read_ready_connection
      end

      def write_ready_connection
        @write_ready_connection = true
      end

      def has_received_write_ready_connection?
        @write_ready_connection
      end
    end

    subject { EventLoop.new(double.as_null_object) }

    def server
      @server
    end

    def socket
      @socket
    end

    after(:all) do
      server.close
      socket.close
    end

    after(:each) do
      subject.stop
      @thread.kill
    end

    before(:all) do
      @server = TCPServer.new('localhost', 9595)
      @socket = TCPSocket.new('localhost', 9595)
    end

    def start_event_loop
      @thread = Thread.new { subject.start }
      @thread.abort_on_exception = true
    end

    it 'notifies when a read operation is ready' do
      fake_server = FakeIO.new(server)

      subject.register_read(fake_server, :read_ready_connection)

      start_event_loop

      eventually { expect(fake_server).to have_received_read_ready_connection }

      subject.deregister_read(fake_server, :read_ready_connection)
    end

    it 'notifies when a write operation is ready' do
      fake_socket = FakeIO.new(socket)

      subject.register_write(fake_socket, :write_ready_connection)

      start_event_loop

      eventually { expect(fake_socket).to have_received_write_ready_connection }

      subject.deregister_write(fake_socket, :write_ready_connection)
    end

    it 'allows to deregister from a read operation' do
      fake_server = FakeIO.new(server)

      subject.register_read(fake_server, :read_ready_connection)

      start_event_loop

      eventually do
        expect(fake_server).to have_received_read_ready_connection
      end

      fake_server.reset

      connection = server.accept_nonblock # accept outstanding connection

      subject.deregister_read(fake_server, :read_ready_connection)

      another_socket = TCPSocket.new('localhost', 9595)

      during(timeout: 0.1) do
        expect(fake_server).to_not have_received_read_ready_connection
      end
    end

    it 'allows to deregister from a write operation' do
      fake_socket = FakeIO.new(socket)

      subject.register_write(fake_socket, :write_ready_connection)

      start_event_loop

      eventually { expect(fake_socket).to have_received_write_ready_connection }

      fake_socket.reset

      subject.deregister_write(fake_socket, :write_ready_connection)

      during(timeout: 0.1) do
        expect(fake_socket).not_to have_received_write_ready_connection
      end
    end
  end
end

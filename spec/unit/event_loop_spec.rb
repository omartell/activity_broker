require 'spec_helper'
require 'support/async_helper'
require 'socket'

module ActivityBroker
  describe EventLoop do
    include AsyncHelper

    let!(:event_loop) { EventLoop.new(double.as_null_object) }

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
      event_loop.stop
      @thread.kill
    end

    before(:all) do
      @server = TCPServer.new('localhost', 9595)
      @socket = TCPSocket.new('localhost', 9595)
    end

    def start_event_loop
      @thread = Thread.new { event_loop.start }
      @thread.abort_on_exception = true
    end

    it 'notifies when a read operation is ready' do
      fake_server = double(to_io: server, connection_read_ready: nil)

      event_loop.register_read(fake_server, :connection_read_ready)

      start_event_loop

      eventually do
        expect(fake_server).to have_received(:connection_read_ready).at_least(:once)
      end

      event_loop.deregister_read(fake_server, :connection_read_ready)
    end

    it 'notifies when a write operation is ready' do
      fake_socket = double(to_io: socket, connection_write_ready: nil)

      event_loop.register_write(fake_socket, :connection_write_ready)

      start_event_loop

      eventually do
        expect(fake_socket).to have_received(:connection_write_ready).at_least(:once)
      end

      event_loop.deregister_write(fake_socket, :connection_write_ready)
    end

    it 'allows to deregister from a read operation' do
      fake_server = double(to_io: server, connection_read_ready: nil)

      event_loop.register_read(fake_server, :connection_read_ready)

      event_loop.deregister_read(fake_server, :connection_read_ready)

      start_event_loop

      on_timeout(timeout: 0.1) do
        expect(fake_server).to_not have_received(:connection_read_ready)
      end
    end

    it 'allows to deregister from a write operation' do
      fake_socket = double(to_io: socket, connection_write_ready: nil)

      event_loop.register_write(fake_socket, :connection_write_ready)

      event_loop.deregister_write(fake_socket, :connection_write_ready)

      start_event_loop

      on_timeout(timeout: 0.1) do
        expect(fake_socket).to_not have_received(:connection_write_ready)
      end
    end

    it 'only allows to register a read-write listener once per object' do
      server = TCPServer.new('localhost', 9494)
      socket = TCPSocket.new('localhost', 9494)
      fake_server = double(to_io: server).tap do |double|
        double.stub(:connection_read_ready) { server.accept_nonblock }
      end

      event_loop.register_read(fake_server, :connection_read_ready)
      event_loop.register_read(fake_server, :connection_read_ready)

      start_event_loop

      on_timeout(timeout: 0.1) do
        expect(fake_server).to have_received(:connection_read_ready).once
      end

      event_loop.deregister_read(fake_server, :connection_read_ready)
      @thread.kill
      server.close
      socket.close
    end
  end
end

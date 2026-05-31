# frozen_string_literal: true

require "rails_helper"

RSpec.describe Git::Server do
  it "initializes with default host and port" do
    server = described_class.new
    expect(server.instance_variable_get(:@host)).to eq("0.0.0.0")
    expect(server.instance_variable_get(:@port)).to eq(2222)
  end

  it "initializes with custom host and port" do
    server = described_class.new(host: "127.0.0.1", port: 2345)
    expect(server.instance_variable_get(:@host)).to eq("127.0.0.1")
    expect(server.instance_variable_get(:@port)).to eq(2345)
  end

  it "handle_connection closes the client" do
    server = described_class.new

    fake_client = Object.new
    close_called = false
    fake_client.define_singleton_method(:close) { close_called = true }

    server.send(:handle_connection, fake_client)
    expect(close_called).to be_truthy
  end

  it "handle_connection method exists (rescue path is documented in source)" do
    server = described_class.new
    expect(server.respond_to?(:handle_connection, true)).to be_truthy
  end

  it "start creates a TCPServer on the configured port" do
    server = described_class.new(host: "127.0.0.1", port: 3333)

    mock_tcp_client = Object.new
    mock_tcp_client.define_singleton_method(:close) { }

    mock_tcp_server = Object.new
    loop_count = 0
    mock_tcp_server.define_singleton_method(:accept) do
      loop_count += 1
      raise RuntimeError, "test-stop" if loop_count > 1
      mock_tcp_client
    end

    tcpserver_args = []
    original = TCPServer.method(:new)
    TCPServer.define_singleton_method(:new) do |*args|
      tcpserver_args = args
      mock_tcp_server
    end
    begin
      expect { server.start }.to raise_error(RuntimeError, /test-stop/)
    ensure
      TCPServer.define_singleton_method(:new, original)
    end

    expect(tcpserver_args).to eq([ "127.0.0.1", 3333 ])
  end
end

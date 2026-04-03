require "test_helper"

class TerminalSessionTest < ActiveSupport::TestCase
  setup do
    @server = servers(:one)
  end

  test "initializes with server" do
    session = TerminalSession.new(server: @server)
    assert_equal @server, session.server
    assert_not session.connected?
  end

  test "builds ssh options from server" do
    session = TerminalSession.new(server: @server)
    opts = session.send(:ssh_options)
    assert_equal @server.port, opts[:port]
    assert opts[:non_interactive]
  end

  test "ssh_options includes key_data when server has private key" do
    @server.ssh_private_key = "-----BEGIN RSA PRIVATE KEY-----\nfakekey\n-----END RSA PRIVATE KEY-----"
    session = TerminalSession.new(server: @server)
    opts = session.send(:ssh_options)
    assert opts[:key_data].present?
    assert_includes opts[:key_data], @server.ssh_private_key
  ensure
    @server.ssh_private_key = nil
  end

  test "ssh_options does not include key_data when server has no private key" do
    @server.ssh_private_key = nil
    session = TerminalSession.new(server: @server)
    opts = session.send(:ssh_options)
    assert_not opts.key?(:key_data)
  end

  test "tracks last activity for timeout" do
    session = TerminalSession.new(server: @server)
    session.touch!
    assert_in_delta Time.current.to_f, session.last_activity_at.to_f, 1.0
  end

  test "timed_out? returns true after inactivity" do
    session = TerminalSession.new(server: @server, timeout: 1.second)
    session.touch!
    sleep 1.1
    assert session.timed_out?
  end

  test "timed_out? returns false when recently active" do
    session = TerminalSession.new(server: @server, timeout: 10.minutes)
    session.touch!
    assert_not session.timed_out?
  end

  test "connect! opens SSH connection for server shell" do
    mock_channel = Object.new
    mock_channel.define_singleton_method(:active?) { true }
    mock_channel.define_singleton_method(:request_pty) { |**_opts, &b| b.call(nil, true) }
    mock_channel.define_singleton_method(:send_channel_request) { |_type, &b| b.call(nil, true) }
    mock_channel.define_singleton_method(:on_data) { |&_b| }
    mock_channel.define_singleton_method(:on_extended_data) { |&_b| }

    mock_ssh = Object.new
    mock_ssh.define_singleton_method(:closed?) { false }
    mock_ssh.define_singleton_method(:open_channel) { |&b| b.call(mock_channel); mock_channel }
    mock_ssh.define_singleton_method(:close) {}

    Net::SSH.define_singleton_method(:start) { |*_args, **_opts, &_block| mock_ssh }

    session = TerminalSession.new(server: @server)
    # We just verify connect! does not raise
    assert_nothing_raised do
      session.connect!
    end
  ensure
    Net::SSH.define_singleton_method(:start, NET_SSH_ORIGINAL_START)
  end

  test "connect! opens SSH connection for app console" do
    mock_channel = Object.new
    mock_channel.define_singleton_method(:active?) { true }
    mock_channel.define_singleton_method(:request_pty) { |**_opts, &b| b.call(nil, true) }
    mock_channel.define_singleton_method(:exec) { |_cmd, &b| b.call(nil, true) }
    mock_channel.define_singleton_method(:on_data) { |&_b| }
    mock_channel.define_singleton_method(:on_extended_data) { |&_b| }

    mock_ssh = Object.new
    mock_ssh.define_singleton_method(:closed?) { false }
    mock_ssh.define_singleton_method(:open_channel) { |&b| b.call(mock_channel); mock_channel }
    mock_ssh.define_singleton_method(:close) {}

    Net::SSH.define_singleton_method(:start) { |*_args, **_opts, &_block| mock_ssh }

    session = TerminalSession.new(server: @server, app_name: "my-app")
    assert_nothing_raised do
      session.connect!
    end
  ensure
    Net::SSH.define_singleton_method(:start, NET_SSH_ORIGINAL_START)
  end

  test "disconnect! closes channel and SSH connection" do
    mock_channel = Object.new
    close_called = false
    mock_channel.define_singleton_method(:close) { close_called = true }

    mock_ssh = Object.new
    ssh_close_called = false
    mock_ssh.define_singleton_method(:close) { ssh_close_called = true }

    session = TerminalSession.new(server: @server)
    session.instance_variable_set(:@channel, mock_channel)
    session.instance_variable_set(:@ssh, mock_ssh)

    session.disconnect!

    assert close_called, "Expected channel.close to be called"
    assert ssh_close_called, "Expected ssh.close to be called"
    assert_nil session.instance_variable_get(:@ssh)
    assert_nil session.instance_variable_get(:@channel)
  end

  test "connected? returns false when ssh is nil" do
    session = TerminalSession.new(server: @server)
    assert_not session.connected?
  end

  test "connected? returns false when ssh is closed" do
    mock_ssh = Object.new
    mock_ssh.define_singleton_method(:closed?) { true }

    mock_channel = Object.new
    mock_channel.define_singleton_method(:active?) { true }

    session = TerminalSession.new(server: @server)
    session.instance_variable_set(:@ssh, mock_ssh)
    session.instance_variable_set(:@channel, mock_channel)

    assert_not session.connected?
  end

  test "send_data does nothing when not connected" do
    session = TerminalSession.new(server: @server)
    assert_nothing_raised do
      session.send_data("some command\n")
    end
  end

  test "resize does nothing when channel is nil" do
    session = TerminalSession.new(server: @server)
    assert_nothing_raised do
      session.resize(120, 30)
    end
  end

  test "process does nothing when ssh is nil" do
    session = TerminalSession.new(server: @server)
    assert_nothing_raised do
      session.process
    end
  end

  test "process handles IOError gracefully" do
    mock_ssh = Object.new
    mock_ssh.define_singleton_method(:closed?) { false }
    mock_ssh.define_singleton_method(:process) { |_t| raise IOError, "stream closed" }
    mock_ssh.define_singleton_method(:close) {}

    mock_channel = Object.new
    mock_channel.define_singleton_method(:close) {}

    session = TerminalSession.new(server: @server)
    session.instance_variable_set(:@ssh, mock_ssh)
    session.instance_variable_set(:@channel, mock_channel)

    assert_nothing_raised do
      session.process
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe TerminalSession do
  let(:server) { servers(:one) }

  # Save Net::SSH.start at file load time so we can restore between tests
  NET_SSH_ORIGINAL_START_FOR_SPEC = Net::SSH.method(:start) unless defined?(NET_SSH_ORIGINAL_START_FOR_SPEC)

  it "initializes with server" do
    session = described_class.new(server: server)
    expect(session.server).to eq(server)
    expect(session.connected?).to be_falsey
  end

  it "builds ssh options from server" do
    session = described_class.new(server: server)
    opts = session.send(:ssh_options)
    expect(opts[:port]).to eq(server.port)
    expect(opts[:non_interactive]).to be_truthy
  end

  it "ssh_options includes key_data when server has private key" do
    server.ssh_private_key = "-----BEGIN RSA PRIVATE KEY-----\nfakekey\n-----END RSA PRIVATE KEY-----"
    session = described_class.new(server: server)
    opts = session.send(:ssh_options)
    expect(opts[:key_data]).to be_present
    expect(opts[:key_data]).to include(server.ssh_private_key)
  ensure
    server.ssh_private_key = nil
  end

  it "ssh_options does not include key_data when server has no private key" do
    server.ssh_private_key = nil
    session = described_class.new(server: server)
    opts = session.send(:ssh_options)
    expect(opts.key?(:key_data)).to be_falsey
  end

  it "tracks last activity for timeout" do
    session = described_class.new(server: server)
    session.touch!
    expect(session.last_activity_at.to_f).to be_within(1.0).of(Time.current.to_f)
  end

  it "timed_out? returns true after inactivity" do
    session = described_class.new(server: server, timeout: 1.second)
    session.touch!
    sleep 1.1
    expect(session.timed_out?).to be_truthy
  end

  it "timed_out? returns false when recently active" do
    session = described_class.new(server: server, timeout: 10.minutes)
    session.touch!
    expect(session.timed_out?).to be_falsey
  end

  it "connect! opens SSH connection for server shell" do
    mock_channel = Object.new
    mock_channel.define_singleton_method(:active?) { true }
    mock_channel.define_singleton_method(:request_pty) { |**_opts, &b| b.call(nil, true) }
    mock_channel.define_singleton_method(:send_channel_request) { |_type, &b| b.call(nil, true) }
    mock_channel.define_singleton_method(:on_data) { |&_b| }
    mock_channel.define_singleton_method(:on_extended_data) { |&_b| }
    mock_channel.define_singleton_method(:on_request) { |_type, &_b| }

    mock_ssh = Object.new
    mock_ssh.define_singleton_method(:closed?) { false }
    mock_ssh.define_singleton_method(:open_channel) { |&b| b.call(mock_channel); mock_channel }
    mock_ssh.define_singleton_method(:close) { }

    Net::SSH.define_singleton_method(:start) { |*_args, **_opts, &_block| mock_ssh }

    session = described_class.new(server: server)
    expect { session.connect! }.not_to raise_error
  ensure
    Net::SSH.define_singleton_method(:start, NET_SSH_ORIGINAL_START_FOR_SPEC)
  end

  it "connect! opens SSH connection for app console" do
    mock_channel = Object.new
    mock_channel.define_singleton_method(:active?) { true }
    mock_channel.define_singleton_method(:request_pty) { |**_opts, &b| b.call(nil, true) }
    mock_channel.define_singleton_method(:exec) { |_cmd, &b| b.call(nil, true) }
    mock_channel.define_singleton_method(:on_data) { |&_b| }
    mock_channel.define_singleton_method(:on_extended_data) { |&_b| }
    mock_channel.define_singleton_method(:on_request) { |_type, &_b| }

    mock_ssh = Object.new
    mock_ssh.define_singleton_method(:closed?) { false }
    mock_ssh.define_singleton_method(:open_channel) { |&b| b.call(mock_channel); mock_channel }
    mock_ssh.define_singleton_method(:close) { }

    Net::SSH.define_singleton_method(:start) { |*_args, **_opts, &_block| mock_ssh }

    session = described_class.new(server: server, app_name: "my-app")
    expect { session.connect! }.not_to raise_error
  ensure
    Net::SSH.define_singleton_method(:start, NET_SSH_ORIGINAL_START_FOR_SPEC)
  end

  it "disconnect! closes channel and SSH connection" do
    mock_channel = Object.new
    close_called = false
    mock_channel.define_singleton_method(:close) { close_called = true }

    mock_ssh = Object.new
    ssh_close_called = false
    mock_ssh.define_singleton_method(:close) { ssh_close_called = true }

    session = described_class.new(server: server)
    session.instance_variable_set(:@channel, mock_channel)
    session.instance_variable_set(:@ssh, mock_ssh)

    session.disconnect!

    expect(close_called).to be_truthy
    expect(ssh_close_called).to be_truthy
    expect(session.instance_variable_get(:@ssh)).to be_nil
    expect(session.instance_variable_get(:@channel)).to be_nil
  end

  it "connected? returns false when ssh is nil" do
    session = described_class.new(server: server)
    expect(session.connected?).to be_falsey
  end

  it "connected? returns false when ssh is closed" do
    mock_ssh = Object.new
    mock_ssh.define_singleton_method(:closed?) { true }

    mock_channel = Object.new
    mock_channel.define_singleton_method(:active?) { true }

    session = described_class.new(server: server)
    session.instance_variable_set(:@ssh, mock_ssh)
    session.instance_variable_set(:@channel, mock_channel)

    expect(session.connected?).to be_falsey
  end

  it "send_data does nothing when not connected" do
    session = described_class.new(server: server)
    expect { session.send_data("some command\n") }.not_to raise_error
  end

  it "resize does nothing when channel is nil" do
    session = described_class.new(server: server)
    expect { session.resize(120, 30) }.not_to raise_error
  end

  it "process does nothing when ssh is nil" do
    session = described_class.new(server: server)
    expect { session.process }.not_to raise_error
  end

  it "process handles IOError gracefully" do
    mock_ssh = Object.new
    mock_ssh.define_singleton_method(:closed?) { false }
    mock_ssh.define_singleton_method(:process) { |_t| raise IOError, "stream closed" }
    mock_ssh.define_singleton_method(:close) { }

    mock_channel = Object.new
    mock_channel.define_singleton_method(:close) { }

    session = described_class.new(server: server)
    session.instance_variable_set(:@ssh, mock_ssh)
    session.instance_variable_set(:@channel, mock_channel)

    expect { session.process }.not_to raise_error
  end

  # --- Mode / build_command tests ---

  it "default mode is :shell when not specified (backward compat)" do
    s = described_class.new(server: server)
    expect(s.mode).to eq(:shell)
  end

  it "app_name kwarg sets mode :enter (deprecated backward-compat alias)" do
    s = described_class.new(server: server, app_name: "x")
    expect(s.mode).to eq(:enter)
  end

  it "build_command for mode :enter assembles dokku enter <app> web without a shell wrapper" do
    s = described_class.new(server: server, mode: :enter, target: "myapp")
    cmd = s.send(:build_command)
    expect(cmd).to eq("enter myapp web")
    expect(cmd).not_to include("/bin/sh")
    expect(cmd).not_to include("-lc")
  end

  it "build_command for mode :enter escapes app name with spaces" do
    s = described_class.new(server: server, mode: :enter, target: "my app")
    cmd = s.send(:build_command)
    expect(cmd).not_to include("my app")  # raw unescaped name must not appear
    expect(cmd.start_with?("enter ")).to be_truthy
    expect(cmd.end_with?(" web")).to be_truthy
  end

  it "build_command for mode :exec uses dokku run with argv args individually escaped" do
    s = described_class.new(server: server, mode: :exec, target: "myapp",
                            argv: [ "bundle", "exec", "rake", "db:migrate" ])
    cmd = s.send(:build_command)
    expect(cmd.start_with?("run myapp ")).to be_truthy
    expect(cmd).to include("bundle")
    expect(cmd).to include("db:migrate")
    expect(cmd).not_to include("/bin/sh")
  end

  it "build_command for mode :exec escapes argv values containing shell metacharacters" do
    s = described_class.new(server: server, mode: :exec, target: "myapp",
                            argv: [ "echo", "hello; rm -rf /" ])
    cmd = s.send(:build_command)
    expect(cmd).not_to match(%r{; rm -rf /})
    expect(cmd).to include("echo")
  end

  it "build_command for mode :exec safely escapes argv containing single quotes" do
    s = described_class.new(server: server, mode: :exec, target: "myapp",
                            argv: [ "echo", "it's broken; rm -rf /" ])
    cmd = s.send(:build_command)
    expect(cmd).not_to match(%r{; rm -rf /})
    expect(cmd.start_with?("run myapp ")).to be_truthy
  end

  it "build_command for mode :db_connect uses plugin:connect" do
    s = described_class.new(server: server, mode: :db_connect, target: "mydb", db_kind: "postgres")
    expect(s.send(:build_command)).to eq("postgres:connect mydb")
  end

  it "build_command for mode :db_connect escapes db name" do
    s = described_class.new(server: server, mode: :db_connect, target: "weird name", db_kind: "postgres")
    cmd = s.send(:build_command)
    expect(cmd).to match(/\Apostgres:connect /)
    expect(cmd).not_to include("weird name")
  end

  it "rejects unknown mode at construction time" do
    expect {
      described_class.new(server: server, mode: :evil, target: "x")
    }.to raise_error(ArgumentError)
  end

  it "requires target for non-shell modes" do
    expect {
      described_class.new(server: server, mode: :enter, target: nil)
    }.to raise_error(ArgumentError)
  end

  it "exec mode with empty argv raises when build_command runs" do
    s = described_class.new(server: server, mode: :exec, target: "myapp", argv: [])
    expect { s.send(:build_command) }.to raise_error(ArgumentError)
  end

  it "db_connect mode without db_kind raises when build_command runs" do
    s = described_class.new(server: server, mode: :db_connect, target: "x", db_kind: nil)
    expect { s.send(:build_command) }.to raise_error(ArgumentError)
  end

  it "on_exit registers a callback that captures exit_code" do
    s = described_class.new(server: server, mode: :enter, target: "myapp")
    captured = nil
    s.on_exit { |code| captured = code }
    s.instance_variable_get(:@on_exit).call(42)
    expect(captured).to eq(42)
  end

  it "exit_code is nil before any SSH exit-status received" do
    s = described_class.new(server: server, mode: :enter, target: "myapp")
    expect(s.exit_code).to be_nil
  end
end

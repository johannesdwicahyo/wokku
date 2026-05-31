# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dokku::Client do
  let(:user) { User.create!(email: "test-dokku@example.com", password: "password123456") }
  let(:team) { Team.create!(name: "Test Team", owner: user) }
  let(:server) { Server.create!(name: "prod", host: "dokku.example.com", team: team) }
  let(:client) { described_class.new(server) }

  it "initializes with server" do
    expect(client.instance_variable_get(:@server)).to eq(server)
  end

  it "raises ConnectionError on auth failure" do
    allow(Net::SSH).to receive(:start).and_raise(Net::SSH::AuthenticationFailed.new("test"))
    expect { client.run("apps:list") }.to raise_error(described_class::ConnectionError)
    expect(server.reload.status).to eq("auth_failed")
  end

  it "raises ConnectionError on connection refused" do
    allow(Net::SSH).to receive(:start).and_raise(Errno::ECONNREFUSED)
    expect { client.run("apps:list") }.to raise_error(described_class::ConnectionError)
    expect(server.reload.status).to eq("unreachable")
  end

  it "raises ConnectionError on SocketError" do
    allow(Net::SSH).to receive(:start).and_raise(SocketError.new("no dns"))
    expect { client.run("apps:list") }.to raise_error(described_class::ConnectionError)
    expect(server.reload.status).to eq("unreachable")
  end

  it "raises ConnectionError on ETIMEDOUT" do
    allow(Net::SSH).to receive(:start).and_raise(Errno::ETIMEDOUT)
    expect { client.run("apps:list") }.to raise_error(described_class::ConnectionError)
  end

  def stub_ssh_session(output: "", error: "", exit_code: 0, exec_success: true, capture_cmd: nil)
    fake_ch = Object.new
    data_handler = ->(_, _) { }
    extended_handler = ->(_, _, _) { }
    exit_handler = ->(_, _) { }
    fake_ch.define_singleton_method(:on_data) { |&b| data_handler = b }
    fake_ch.define_singleton_method(:on_extended_data) { |&b| extended_handler = b }
    fake_ch.define_singleton_method(:on_request) { |_name, &b| exit_handler = b }
    fake_ch.define_singleton_method(:exec) do |cmd, &exec_block|
      capture_cmd&.call(cmd)
      exec_block.call(fake_ch, exec_success)
      next unless exec_success
      data_handler.call(nil, output) unless output.empty?
      extended_handler.call(nil, nil, error) unless error.empty?
      buf = Object.new
      buf.define_singleton_method(:read_long) { exit_code }
      exit_handler.call(nil, buf)
    end

    fake_channel = Object.new
    fake_channel.define_singleton_method(:wait) { true }

    fake_ssh = Object.new
    fake_ssh.define_singleton_method(:open_channel) { |&b| b.call(fake_ch); fake_channel }

    allow(Net::SSH).to receive(:start).and_yield(fake_ssh)
  end

  it "run returns stripped output on success" do
    stub_ssh_session(output: "  hello  ", exit_code: 0)
    expect(client.run("version")).to eq("hello")
  end

  it "run raises CommandError on non-zero exit code with stderr attached" do
    stub_ssh_session(output: "", error: "boom", exit_code: 5)
    expect { client.run("bad") }.to raise_error(described_class::CommandError) do |err|
      expect(err.exit_code).to eq(5)
      expect(err.stderr).to eq("boom")
    end
  end

  it "run raises ConnectionError when exec fails to start" do
    stub_ssh_session(exec_success: false)
    expect { client.run("x") }.to raise_error(described_class::ConnectionError)
  end

  it "run sends the command raw when ssh_user is dokku" do
    server.update!(ssh_user: "dokku")
    captured = nil
    stub_ssh_session(capture_cmd: ->(c) { captured = c })
    client.run("apps:list")
    expect(captured).to eq("apps:list")
  end

  it "run prefixes with 'dokku' when ssh_user is not dokku" do
    server.update!(ssh_user: "ubuntu")
    captured = nil
    stub_ssh_session(capture_cmd: ->(c) { captured = c })
    client.run("apps:list")
    expect(captured).to eq("dokku apps:list")
  end

  it "connected? returns true when version succeeds" do
    stub_ssh_session(output: "0.35.0", exit_code: 0)
    expect(client.connected?).to be_truthy
  end

  it "connected? returns false on ConnectionError" do
    allow(Net::SSH).to receive(:start).and_raise(Errno::ECONNREFUSED)
    expect(client.connected?).to eq(false)
  end

  it "connected? returns false on CommandError" do
    stub_ssh_session(exit_code: 1)
    expect(client.connected?).to eq(false)
  end

  it "run translates Timeout::Error to ConnectionError with command in message" do
    allow(Net::SSH).to receive(:start).and_raise(Timeout::Error)
    expect { client.run("apps:list", timeout: 1) }.to raise_error(described_class::ConnectionError) do |err|
      expect(err.message).to match(/timed out after 1s/)
      expect(err.message).to match(/apps:list/)
    end
  end

  it "run_streaming yields chunks via the provided block" do
    chunks = []
    stub_ssh_session(output: "hello", error: "warn", exit_code: 0)
    client.run_streaming("tail") { |data| chunks << data }
    expect(chunks).to include("hello")
    expect(chunks).to include("warn")
  end
end

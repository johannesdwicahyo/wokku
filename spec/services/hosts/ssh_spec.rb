# frozen_string_literal: true

require "rails_helper"

# Hosts::Ssh is the app's only raw SSH transport (the dokku wrapper layer
# it was extracted from died in W7 Phase 4).
RSpec.describe Hosts::Ssh do
  let(:user) { User.create!(email: "test-hosts-ssh@example.com", password: "password123456") }
  let(:team) { Team.create!(name: "Test Team", owner: user) }
  let(:server) { Server.create!(name: "prod", host: "dokku.example.com", team: team) }
  let(:ssh) { described_class.new(server) }

  it "TimeoutError is a ConnectionError — callers rescuing ConnectionError catch both" do
    expect(described_class::TimeoutError.superclass).to eq(described_class::ConnectionError)
  end

  def stub_ssh_session(output: "", error: "", exit_code: 0, exec_success: true, capture_cmd: nil, capture_user: nil)
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

    allow(Net::SSH).to receive(:start) do |_host, ssh_user, _opts, &blk|
      capture_user&.call(ssh_user)
      blk.call(fake_ssh)
    end
  end

  describe "#run_raw" do
    it "connects as root and sends the command verbatim, returning stripped stdout" do
      server.update!(ssh_user: "ubuntu")
      captured_cmd = nil
      captured_user = nil
      stub_ssh_session(output: "  hello  ", exit_code: 0,
                       capture_cmd: ->(c) { captured_cmd = c }, capture_user: ->(u) { captured_user = u })
      expect(ssh.run_raw("docker images")).to eq("hello")
      expect(captured_user).to eq("root")
      expect(captured_cmd).to eq("docker images")
    end

    it "raises CommandError on non-zero exit code with stderr attached" do
      stub_ssh_session(output: "", error: "no such image", exit_code: 1)
      expect { ssh.run_raw("docker rmi missing:tag") }.to raise_error(described_class::CommandError) do |err|
        expect(err.exit_code).to eq(1)
        expect(err.stderr).to eq("no such image")
      end
    end

    it "raises ConnectionError on connection refused and marks the server unreachable" do
      allow(Net::SSH).to receive(:start).and_raise(Errno::ECONNREFUSED)
      expect { ssh.run_raw("docker images") }.to raise_error(described_class::ConnectionError)
      expect(server.reload.status).to eq("unreachable")
    end
  end

  describe "#run_raw_streaming" do
    it "connects as root, sends the command verbatim, and yields stdout chunks" do
      server.update!(ssh_user: "ubuntu")
      captured_cmd = nil
      captured_user = nil
      chunks = []
      stub_ssh_session(output: "TARBYTES", error: "tar: warning", exit_code: 0,
                       capture_cmd: ->(c) { captured_cmd = c }, capture_user: ->(u) { captured_user = u })
      ssh.run_raw_streaming("tar -czf - -C /x .", include_stderr: false) { |d| chunks << d }
      expect(captured_user).to eq("root")
      expect(captured_cmd).to eq("tar -czf - -C /x .")
      expect(chunks).to eq([ "TARBYTES" ])
    end

    it "raises CommandError with the stderr tail on non-zero exit" do
      stub_ssh_session(output: "", error: "tar: /nope: No such file", exit_code: 2)
      expect { ssh.run_raw_streaming("tar -czf - -C /nope .") { |_| } }
        .to raise_error(described_class::CommandError, /No such file/) do |err|
          expect(err.exit_code).to eq(2)
        end
    end
  end

  describe "#connected?" do
    it "probes with a bare root no-op and returns true on success" do
      captured_cmd = nil
      captured_user = nil
      stub_ssh_session(output: "", exit_code: 0,
                       capture_cmd: ->(c) { captured_cmd = c }, capture_user: ->(u) { captured_user = u })
      expect(ssh.connected?).to be true
      expect(captured_user).to eq("root")
      expect(captured_cmd).to eq("true")
    end

    it "returns false on ConnectionError" do
      allow(Net::SSH).to receive(:start).and_raise(Errno::ECONNREFUSED)
      expect(ssh.connected?).to eq(false)
    end
  end
end

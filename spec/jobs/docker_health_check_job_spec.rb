# frozen_string_literal: true

require "rails_helper"

RSpec.describe DockerHealthCheckJob, type: :job do
  let(:server) { create(:server, ssh_private_key: "fake-key-#{SecureRandom.hex(4)}") }

  def stub_ssh_returning(value)
    fake_ssh = double("ssh")
    allow(fake_ssh).to receive(:exec!).and_return(value)
    allow(Net::SSH).to receive(:start).and_yield(fake_ssh)
  end

  it "records active status when systemctl returns active" do
    stub_ssh_returning("active\n")
    described_class.new.perform(server.id)
    expect(server.reload.docker_status).to eq("active")
    expect(server.docker_status_checked_at).to be_present
  end

  it "records failed status and reports to Sentry on transition" do
    stub_ssh_returning("failed\n")
    expect(Sentry).to receive(:capture_message).with(
      /Docker daemon non-active/,
      hash_including(level: :error)
    )
    described_class.new.perform(server.id)
    expect(server.reload.docker_status).to eq("failed")
  end

  it "does NOT report to Sentry again when status stays failed across polls" do
    server.update!(docker_status: "failed", docker_status_checked_at: 5.minutes.ago)
    stub_ssh_returning("failed\n")
    expect(Sentry).not_to receive(:capture_message)
    described_class.new.perform(server.id)
  end

  it "marks unreachable on network errors" do
    allow(Net::SSH).to receive(:start).and_raise(Errno::EHOSTUNREACH, "no route")
    described_class.new.perform(server.id)
    expect(server.reload.docker_status).to eq("unreachable")
  end

  it "is a no-op when ssh_private_key is blank" do
    server.update_column(:ssh_private_key, nil)
    expect(Net::SSH).not_to receive(:start)
    described_class.new.perform(server.id)
    expect(server.reload.docker_status).to be_nil
  end

  describe "host SSH user" do
    def capture_ssh
      seen = {}
      fake_ssh = double("ssh")
      allow(fake_ssh).to receive(:exec!) { |cmd| seen[:cmd] = cmd; "active\n" }
      allow(Net::SSH).to receive(:start) { |_h, user, **_o, &blk| seen[:user] = user; blk.call(fake_ssh) }
      seen
    end

    it "as root, probes systemctl directly" do
      seen = capture_ssh
      described_class.new.perform(server.id)
      expect(seen).to eq(user: "root", cmd: "systemctl is-active docker 2>&1")
    end

    it "as a non-root user, probes through the sudo helper" do
      allow(Wokku.config).to receive(:host_ssh_user).and_return("wokku")
      seen = capture_ssh
      described_class.new.perform(server.id)
      expect(seen).to eq(user: "wokku", cmd: "sudo -n /usr/local/sbin/wokku-docker-health 2>&1")
      expect(server.reload.docker_status).to eq("active")
    end
  end

  # 2026-09-21: sshd died while the host kept heartbeating; nobody knew for days.
  describe "SSH down alert" do
    def fail_ssh = allow(Net::SSH).to(receive(:start).and_raise(Errno::ECONNREFUSED, "refused"))
    before { server.update_columns(heartbeat_at: Time.current, heartbeat_status: "ok") }

    it "emails on the second failed probe in a row while the host is still heartbeating" do
      fail_ssh
      expect { described_class.new.perform(server.id) }.not_to have_enqueued_mail(OpsMailer, :ssh_down)
      expect { described_class.new.perform(server.id) }.to have_enqueued_mail(OpsMailer, :ssh_down)
      expect(server.reload.ssh_alerted_at).to be_present
    end

    it "emails once, not on every poll while SSH stays down" do
      fail_ssh
      2.times { described_class.new.perform(server.id) }
      expect { described_class.new.perform(server.id) }.not_to have_enqueued_mail(OpsMailer, :ssh_down)
    end

    it "treats a refused login (key rejected) as SSH down too" do
      allow(Net::SSH).to receive(:start).and_raise(Net::SSH::AuthenticationFailed, "wokku")
      described_class.new.perform(server.id)
      expect { described_class.new.perform(server.id) }.to have_enqueued_mail(OpsMailer, :ssh_down)
    end

    it "leaves it to the Host DOWN mail when the host stopped heartbeating" do
      server.update_columns(heartbeat_at: 1.hour.ago)
      fail_ssh
      expect { 2.times { described_class.new.perform(server.id) } }.not_to have_enqueued_mail(OpsMailer, :ssh_down)
    end

    it "emails recovery once SSH works again after an alert" do
      server.update_columns(docker_status: "unreachable", ssh_alerted_at: 20.minutes.ago)
      stub_ssh_returning("active\n")
      expect { described_class.new.perform(server.id) }.to have_enqueued_mail(OpsMailer, :ssh_recovered)
      expect(server.reload.ssh_alerted_at).to be_nil
    end

    it "sends no recovery mail when no alert went out" do
      server.update_columns(docker_status: "unreachable")
      stub_ssh_returning("active\n")
      expect { described_class.new.perform(server.id) }.not_to have_enqueued_mail(OpsMailer, :ssh_recovered)
    end
  end
end

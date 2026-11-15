require "rails_helper"

RSpec.describe OpsMailer do
  let(:server) { create(:server, name: "jkt-01") }

  around do |example|
    original = ENV["ADMIN_EMAIL"]
    ENV["ADMIN_EMAIL"] = "founder@example.com"
    example.run
  ensure
    ENV["ADMIN_EMAIL"] = original
  end

  describe "#host_down" do
    it "pages the founder with host name and last-seen time" do
      server.update_columns(heartbeat_at: Time.utc(2026, 7, 4, 12, 0))
      mail = described_class.host_down(server)
      expect(mail.to).to eq([ "founder@example.com" ])
      expect(mail.subject).to include("DOWN").and include("jkt-01")
      expect(mail.body.encoded).to include("2026-07-04 12:00")
    end

    it "is a no-op without ADMIN_EMAIL" do
      ENV["ADMIN_EMAIL"] = nil
      expect(described_class.host_down(server).message).to be_a(ActionMailer::Base::NullMail)
    end
  end

  describe "#starter_check_failed" do
    it "lists each failed starter with its reason" do
      mail = described_class.starter_check_failed({ "go" => "build failed: toolchain not available" }, 14)
      expect(mail.subject).to include("1 of 14 starters failed")
      expect(mail.body.encoded).to include("- go: build failed: toolchain not available")
    end
  end

  describe "#host_recovered" do
    it "sends the all-clear" do
      server.update_columns(heartbeat_status: "ok")
      mail = described_class.host_recovered(server)
      expect(mail.subject).to include("recovered").and include("jkt-01")
    end

    it "sends a DEGRADED-flavored subject when the host resumes degraded" do
      server.update_columns(heartbeat_status: "degraded")
      mail = described_class.host_recovered(server)
      expect(mail.subject).to include("DEGRADED").and include("jkt-01")
    end
  end

  describe "#storage_backup_stale" do
    it "names the real systemd timers" do
      body = described_class.storage_backup_stale(server, nil).body.encoded
      expect(body).to include("rustfs-backup.timer").and include("rustfs-backup-drill.timer")
      expect(body).not_to include("rustfs-r2-sync")
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe EnableSslJob, type: :job do
  let(:server)  { create(:server) }
  let(:app)     { create(:app_record, server: server) }
  let(:domain)  { Domain.create!(app_record: app, hostname: "example.com", dns_verified: true, pending_action: "ssl_enable") }

  before do
    allow_any_instance_of(AppRecord).to receive(:broadcast_action_toast)
  end

  describe "managed subdomain (wildcard cert)" do
    it "marks a managed subdomain SSL-enabled with a certificate record pinned to the wildcard expiry" do
      create(:wildcard_certificate, fullchain_pem: "FC", key_pem: "KEY", expires_at: 60.days.from_now)
      managed_domain = Domain.create!(
        app_record: app,
        hostname: "#{app.name}.wokku.app",
        pending_action: "ssl_enable"
      )

      described_class.perform_now(managed_domain.id)

      managed_domain.reload
      expect(managed_domain.ssl_enabled).to be(true)
      expect(managed_domain.certificate.auto_renew).to be(false)
      expect(managed_domain.certificate.expires_at).to be_within(1.day).of(60.days.from_now)
    end

    it "still marks ssl_enabled when no wildcard cert row exists yet (Caddy config catches up on issuance)" do
      managed_domain = Domain.create!(
        app_record: app,
        hostname: "#{app.name}.wokku.cloud",
        pending_action: "ssl_enable"
      )

      described_class.perform_now(managed_domain.id)

      managed_domain.reload
      expect(managed_domain.ssl_enabled).to be(true)
      expect(managed_domain.certificate.auto_renew).to be(true)
    end

    it "does not require dns_verified for a managed subdomain" do
      managed_domain = Domain.create!(
        app_record: app,
        hostname: "#{app.name}.wokku.app",
        dns_verified: false,
        pending_action: "ssl_enable"
      )
      described_class.perform_now(managed_domain.id)
      expect(managed_domain.reload.ssl_enabled).to be(true)
    end
  end

  describe "guard clauses" do
    it "no-ops when the domain does not exist" do
      expect { described_class.perform_now("00000000-0000-0000-0000-000000000000") }.not_to raise_error
    end

    it "no-ops when the domain has no app_record" do
      allow(Domain).to receive(:find_by).with(id: domain.id).and_return(domain)
      allow(domain).to receive(:app_record).and_return(nil)
      expect { described_class.perform_now(domain.id) }.not_to raise_error
    end
  end

  describe "happy path" do
    it "enables SSL, flips the domain, creates a certificate, and toasts success" do
      expect {
        described_class.perform_now(domain.id)
      }.to change { Certificate.count }.by(1)

      domain.reload
      expect(domain.ssl_enabled).to be(true)
      expect(domain.pending_action).to be_nil
      expect(domain.certificate).to be_present
      expect(domain.certificate.auto_renew).to be(true)
      expect(domain.certificate.expires_at).to be_within(1.day).of(90.days.from_now)
    end

    it "does not create a duplicate certificate when one already exists" do
      domain.create_certificate!(auto_renew: true, expires_at: 30.days.from_now)

      expect {
        described_class.perform_now(domain.id)
      }.not_to change { Certificate.count }
    end

    it "logs an activity on success" do
      expect(Activity).to receive(:log).with(
        hash_including(action: "domain.ssl_enabled", target: domain)
      )
      described_class.perform_now(domain.id)
    end

    it "broadcasts a success toast" do
      allow_any_instance_of(AppRecord).to receive(:broadcast_action_toast) do |_app, level:, message:|
        expect(level).to eq("success")
        expect(message).to include("SSL enabled")
      end
      described_class.perform_now(domain.id)
    end

    it "swallows Activity.log errors via rescue nil" do
      allow(Activity).to receive(:log).and_raise(StandardError, "boom")
      expect { described_class.perform_now(domain.id) }.not_to raise_error
    end
  end

  describe "unverified custom domain" do
    let(:unverified) { Domain.create!(app_record: app, hostname: "shop.customer.com", dns_verified: false, pending_action: "ssl_enable") }

    it "clears pending_action, leaves ssl off, and toasts an error" do
      captured = {}
      allow_any_instance_of(AppRecord).to receive(:broadcast_action_toast) do |_a, level:, message:|
        captured[:level] = level
        captured[:message] = message
      end

      expect {
        described_class.perform_now(unverified.id)
      }.not_to change { Certificate.count }

      unverified.reload
      expect(unverified.ssl_enabled).to be_falsey
      expect(unverified.pending_action).to be_nil
      expect(captured[:level]).to eq("error")
      expect(captured[:message]).to include("DNS is not verified")
    end
  end
end

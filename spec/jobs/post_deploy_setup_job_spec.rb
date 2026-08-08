# frozen_string_literal: true

require "rails_helper"

RSpec.describe PostDeploySetupJob, type: :job do
  let(:app) { app_records(:one) }

  # CF creds are set per-spec (NOT globally — see rails_helper note). The
  # job's setup_domain_record reads Wokku.config.canonical_domain (a
  # config read, no token needed), but keeping the flag set here mirrors
  # production where a canonical zone is configured either way.
  around do |example|
    orig_token = ENV["CLOUDFLARE_API_TOKEN"]
    orig_zone  = ENV["CLOUDFLARE_ZONE_ID"]
    ENV["CLOUDFLARE_API_TOKEN"] = "TEST_CF_TOKEN"
    ENV["CLOUDFLARE_ZONE_ID"]   = "TEST_CF_ZONE"
    example.run
  ensure
    ENV["CLOUDFLARE_API_TOKEN"] = orig_token
    ENV["CLOUDFLARE_ZONE_ID"]   = orig_zone
  end

  before do
    allow(Wokku.config.dns_provider).to receive(:create_app_record).and_return(nil)
  end

  it "returns early when app not found" do
    expect(Wokku.config.dns_provider).not_to receive(:create_app_record)
    described_class.perform_now("00000000-0000-7000-8000-000000000000")
  end

  # W7 Phase 3: control-plane legs only — the post-deploy pass never opens
  # a dokku SSH client, for ANY app (adopted non-native included).
  it "never instantiates a dokku client" do
    expect(Hosts::Ssh).not_to receive(:new)
    described_class.perform_now(app.id)
  end

  it "marks the app running and records a release" do
    app.releases.update_all(created_at: 1.hour.ago) # age past the 30s dedupe guard
    expect { described_class.perform_now(app.id) }.to change { app.releases.count }.by(1)
    expect(app.reload.status).to eq("running")
  end

  it "creates a Domain record for the default wokku.cloud subdomain" do
    expect { described_class.perform_now(app.id) }.to change { app.domains.count }.by(1)
    expect(app.domains.exists?(hostname: "#{app.name}.wokku.cloud")).to be true
  end

  it "swallows Cloudflare errors and still sets up the rest" do
    allow(Wokku.config.dns_provider).to receive(:create_app_record)
      .and_raise(StandardError, "cloudflare down")
    expect { described_class.perform_now(app.id) }.not_to raise_error
    expect(app.reload.domains.exists?(hostname: "#{app.name}.wokku.cloud")).to be true
  end

  describe "domain provisioning for a NEW app" do
    it "creates only the canonical (.wokku.app) Domain row, not .wokku.cloud" do
      allow(Wokku.config).to receive(:canonical_domain).and_return("wokku.app")
      app = create(:app_record)
      described_class.new.send(:setup_domain_record, app)
      hostnames = app.domains.reload.pluck(:hostname)
      expect(hostnames).to include("#{app.name}.wokku.app")
      expect(hostnames).not_to include("#{app.name}.wokku.cloud")
    end
  end

  it "is idempotent — running twice doesn't create duplicate domain" do
    described_class.perform_now(app.id)
    expect { described_class.perform_now(app.id) }.not_to change { app.domains.count }
  end

  it "enqueues the shared-addon auto-provision pass" do
    expect { described_class.perform_now(app.id) }
      .to have_enqueued_job(AutoProvisionSharedAddonsJob).with(app.id)
  end
end

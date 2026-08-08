# frozen_string_literal: true

require "rails_helper"

RSpec.describe UpdateAppCdnJob, type: :job do
  let(:user) { User.create!(email: "cdn-job@example.com", password: "password123456") }
  let(:team) { Team.create!(name: "CDN", owner: user) }
  let(:server) { Server.create!(name: "s", host: "1.2.3.4", team: team) }
  let!(:app) do
    AppRecord.create!(
      name: "cdn-app", server: server, team: team, creator: user,
      status: :running, cloudflare_proxied: true
    )
  end

  # Same save/restore pattern as post_deploy_setup_job_spec — a bare `||=`
  # here leaked test-zone creds into later files (Cloudflare::Dns.enabled?
  # flipped true) and broke wokkud_native_guards_spec's PostDeploySetupJob
  # example with a real HTTP attempt.
  around do |example|
    orig_token = ENV["CLOUDFLARE_API_TOKEN"]
    orig_zone  = ENV["CLOUDFLARE_ZONE_ID"]
    ENV["CLOUDFLARE_API_TOKEN"] ||= "test-token"
    ENV["CLOUDFLARE_ZONE_ID"]   ||= "test-zone"
    example.run
  ensure
    ENV["CLOUDFLARE_API_TOKEN"] = orig_token
    ENV["CLOUDFLARE_ZONE_ID"]   = orig_zone
  end

  it "no-ops on unknown app" do
    expect(Wokku.config.dns_provider).not_to receive(:set_proxied!)
    described_class.new.perform(SecureRandom.uuid, true)
  end

  it "calls Wokku.config.dns_provider#set_proxied! with the requested state" do
    expect(Wokku.config.dns_provider).to receive(:set_proxied!).with(app.name, proxied: true)
    described_class.new.perform(app.id, true)
  end

  it "rolls back the DB flag when the Cloudflare call fails" do
    allow(Wokku.config.dns_provider).to receive(:set_proxied!)
      .and_raise(Wokku::Providers::DnsError, "rate limited")
    described_class.new.perform(app.id, true)
    expect(app.reload.cloudflare_proxied).to eq(false)
  end
end

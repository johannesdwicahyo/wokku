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

  before do
    ENV["CLOUDFLARE_API_TOKEN"] ||= "test-token"
    ENV["CLOUDFLARE_ZONE_ID"]   ||= "test-zone"
  end

  it "no-ops on unknown app" do
    expect_any_instance_of(Cloudflare::Dns).not_to receive(:set_proxied!)
    described_class.new.perform(SecureRandom.uuid, true)
  end

  it "calls Cloudflare::Dns#set_proxied! with the requested state" do
    expect_any_instance_of(Cloudflare::Dns).to receive(:set_proxied!).with(app.name, proxied: true)
    described_class.new.perform(app.id, true)
  end

  it "rolls back the DB flag when the Cloudflare call fails" do
    allow_any_instance_of(Cloudflare::Dns).to receive(:set_proxied!)
      .and_raise(Cloudflare::Dns::ApiError, "rate limited")
    described_class.new.perform(app.id, true)
    expect(app.reload.cloudflare_proxied).to eq(false)
  end
end

require "rails_helper"

RSpec.describe Apps::Settings::CdnToggle do
  let(:app) { app_records(:one) }

  describe "#enable!" do
    it "flips cloudflare_proxied to true and enqueues UpdateAppCdnJob" do
      app.update!(cloudflare_proxied: false)
      expect {
        described_class.new(app).enable!
      }.to change { app.reload.cloudflare_proxied }.from(false).to(true)
        .and have_enqueued_job(UpdateAppCdnJob).with(app.id, true)
    end

    it "is idempotent when already enabled" do
      app.update!(cloudflare_proxied: true)
      expect { described_class.new(app).enable! }.not_to change { app.reload.cloudflare_proxied }
    end
  end

  describe "#disable!" do
    it "flips cloudflare_proxied to false and enqueues UpdateAppCdnJob" do
      app.update!(cloudflare_proxied: true)
      expect {
        described_class.new(app).disable!
      }.to change { app.reload.cloudflare_proxied }.from(true).to(false)
        .and have_enqueued_job(UpdateAppCdnJob).with(app.id, false)
    end
  end

  describe "#enabled?" do
    it "mirrors cloudflare_proxied" do
      app.update!(cloudflare_proxied: true)
      expect(described_class.new(app).enabled?).to be true
      app.update!(cloudflare_proxied: false)
      expect(described_class.new(app).enabled?).to be false
    end
  end
end

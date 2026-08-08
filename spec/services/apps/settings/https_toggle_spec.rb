require "rails_helper"

RSpec.describe Apps::Settings::HttpsToggle do
  let(:app) { app_records(:one) }

  it "defaults to enabled (Caddy always redirects today — recorded intent)" do
    expect(described_class.new(app).enabled?).to be true
  end

  describe "#enable!" do
    it "persists https_redirect true and returns true" do
      app.update!(https_redirect: false)
      expect(described_class.new(app).enable!).to be true
      expect(app.reload.https_redirect).to be true
    end
  end

  describe "#disable!" do
    it "persists https_redirect false and returns false" do
      expect(described_class.new(app).disable!).to be false
      expect(app.reload.https_redirect).to be false
    end
  end

  describe "#enabled?" do
    it "reads the persisted flag" do
      app.update!(https_redirect: false)
      expect(described_class.new(app).enabled?).to be false
    end
  end

  it "never talks to Dokku" do
    expect(Hosts::Ssh).not_to receive(:new)
    toggle = described_class.new(app)
    toggle.enable!
    toggle.disable!
    toggle.enabled?
  end
end

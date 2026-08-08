require "rails_helper"

RSpec.describe Apps::Settings::MaintenanceToggle do
  let(:app) { app_records(:one) }

  it "defaults to disabled" do
    expect(described_class.new(app).enabled?).to be false
  end

  describe "#enable!" do
    it "persists maintenance_mode true and returns true" do
      expect(described_class.new(app).enable!).to be true
      expect(app.reload.maintenance_mode).to be true
    end
  end

  describe "#disable!" do
    it "persists maintenance_mode false and returns false" do
      app.update!(maintenance_mode: true)
      expect(described_class.new(app).disable!).to be false
      expect(app.reload.maintenance_mode).to be false
    end
  end

  describe "#enabled?" do
    it "reads the persisted flag" do
      app.update!(maintenance_mode: true)
      expect(described_class.new(app).enabled?).to be true
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

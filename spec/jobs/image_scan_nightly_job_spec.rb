# frozen_string_literal: true

require "rails_helper"

RSpec.describe ImageScanNightlyJob do
  let(:app_record) { create(:app_record) }
  let!(:deploy) { create(:deploy, :succeeded, app_record: app_record, image_ref: "r/x:1") }

  before do
    allow(Wokku.config).to receive(:image_scans?).and_return(true)
    app_record.releases.create!(deploy: deploy, description: "d")
  end

  it "enqueues a nightly scan for a stale app" do
    described_class.perform_now
    expect(ImageScan.pending.where(app_record: app_record).first).to be_via_nightly
  end

  it "skips an app with a fresh succeeded scan" do
    ImageScan.create!(app_record: app_record, server: app_record.server, image_ref: "r/x:1", status: :succeeded)
    expect { described_class.perform_now }.not_to change(ImageScan, :count)
  end

  it "enqueues when only an older image has a fresh scan" do
    ImageScan.create!(app_record: app_record, server: app_record.server, image_ref: "r/old:0", status: :succeeded)
    expect { described_class.perform_now }.to change(ImageScan, :count).by(1)
  end

  it "scans again once the last scan is over 20h old" do
    ImageScan.create!(app_record: app_record, server: app_record.server, image_ref: "r/x:1", status: :succeeded, created_at: 21.hours.ago)
    expect { described_class.perform_now }.to change(ImageScan, :count).by(1)
  end
end

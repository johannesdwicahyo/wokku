# frozen_string_literal: true

require "rails_helper"

RSpec.describe ImageScanJanitorJob do
  let(:app_record) { create(:app_record) }

  def scan(**attrs) = ImageScan.create!({ app_record: app_record, server: app_record.server, image_ref: "r/x:1", status: :succeeded }.merge(attrs))

  it "keeps the 10 newest per app" do
    12.times { |i| scan(created_at: i.hours.ago) }
    described_class.perform_now
    expect(ImageScan.count).to eq(10)
  end

  it "deletes skipped rows and does not count them toward the 10 kept" do
    10.times { |i| scan(created_at: i.hours.ago) }
    skipped = scan(status: :skipped)
    described_class.perform_now
    expect(ImageScan.where(id: skipped.id)).to be_empty
    expect(ImageScan.count).to eq(10)
  end

  it "times out claims older than 15 minutes" do
    stuck = scan(status: :claimed, claimed_at: 20.minutes.ago)
    described_class.perform_now
    expect(stuck.reload).to have_attributes(status: "failed", error_code: "timeout")
  end

  it "leaves a fresh claim alone" do
    live = scan(status: :claimed, claimed_at: 1.minute.ago)
    described_class.perform_now
    expect(live.reload).to be_claimed
  end
end

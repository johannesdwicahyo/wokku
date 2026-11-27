# frozen_string_literal: true

require "rails_helper"

RSpec.describe ImageScans::Enqueue do
  let(:app_record) { create(:app_record) }
  let(:deploy) { create(:deploy, :succeeded, app_record: app_record, image_ref: "127.0.0.1:5000/wokku/x:1") }

  def call(d = deploy) = described_class.call(app: app_record, deploy: d, trigger: :deploy)

  it "is nil when the config is off" do
    expect(call).to be_nil
    expect(ImageScan.count).to eq(0)
  end

  context "with image scans on" do
    before { allow(Wokku.config).to receive(:image_scans?).and_return(true) }

    it "creates a pending scan on the app's server" do
      scan = call
      expect(scan).to be_pending
      expect(scan).to have_attributes(image_ref: deploy.image_ref, server_id: app_record.server_id, deploy_id: deploy.id)
    end

    it "skips the earlier pending scan" do
      first = call
      call
      expect(first.reload).to be_skipped
      expect(ImageScan.pending.count).to eq(1)
    end

    it "creates a new pending scan while another is claimed" do
      call.update!(status: :claimed, claimed_at: Time.current)
      expect(call).to be_pending
    end

    it "is nil for a blank image_ref" do
      expect(call(create(:deploy, app_record: app_record, image_ref: nil))).to be_nil
    end

    it "never raises" do
      allow(ImageScan).to receive(:create!).and_raise("boom")
      expect(call).to be_nil
    end
  end
end

require "rails_helper"

RSpec.describe Deploy do
  it "defaults to pending status" do
    deploy = Deploy.new(app_record: app_records(:one))
    expect(deploy.status).to eq("pending")
  end

  it "enum status values" do
    deploy = deploys(:one)
    expect(deploy.pending?).to be true
    deploy.building!
    expect(deploy.building?).to be true
  end

  it "duration returns difference between started_at and finished_at" do
    deploy = deploys(:one)
    expect(deploy.duration).not_to be_nil
    expect(deploy.duration).to be > 0
  end

  describe "#wokkud_image_ref" do
    it "is the local-registry build ref keyed on the full deploy id" do
      deploy = create(:deploy)
      expect(deploy.wokkud_image_ref)
        .to eq("127.0.0.1:5000/wokku/#{deploy.app_record.name}:#{deploy.id}")
    end
  end
end

RSpec.describe Deploy, ".in_progress_for" do
  it "returns pending/building deploys of the scope only, newest first" do
    mine = create(:app_record)
    other = create(:app_record)
    old = create(:deploy, app_record: mine, status: :building, created_at: 2.minutes.ago)
    fresh = create(:deploy, app_record: mine, status: :pending)
    create(:deploy, app_record: mine, status: :succeeded)
    create(:deploy, app_record: other, status: :building)

    expect(Deploy.in_progress_for(AppRecord.where(id: mine.id))).to eq([ fresh, old ])
  end

  it "excludes orphaned deploys older than the deploy window" do
    app = create(:app_record)
    create(:deploy, app_record: app, status: :building, created_at: 3.hours.ago)
    live = create(:deploy, app_record: app, status: :building, created_at: 5.minutes.ago)
    expect(Deploy.in_progress_for(AppRecord.where(id: app.id))).to eq([ live ])
  end
end

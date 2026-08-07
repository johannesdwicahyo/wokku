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

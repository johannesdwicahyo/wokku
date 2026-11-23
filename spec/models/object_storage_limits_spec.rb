# frozen_string_literal: true

require "rails_helper"

RSpec.describe "object_storage_limits seam" do
  after { Wokku.config.object_storage_limits = nil }

  let(:team) { create(:object_storage_bucket).team }

  def limits(**h) = Wokku.config.object_storage_limits = ->(_team) { { free: false, max_buckets: nil, max_total_gb: nil }.merge(h) }

  it "defaults to today's behaviour (free follows the plan, no caps for paid)" do
    allow(team).to receive(:current_plan).and_return(instance_double(Plan, free?: true))
    expect(Wokku.config.object_storage_limits.call(team)).to eq(free: true, max_buckets: nil, max_total_gb: 1)
    allow(team).to receive(:current_plan).and_return(instance_double(Plan, free?: false))
    expect(Wokku.config.object_storage_limits.call(team)).to eq(free: false, max_buckets: nil, max_total_gb: nil)
  end

  it "refuses a new bucket once max_buckets is reached, with a clear message" do
    limits(max_buckets: 1)
    expect(ObjectStorageBucket.free_team_limit_reached?(team)).to be true
    expect(ObjectStorageBucket.limit_message(team)).to match(/includes 1 object storage bucket/)
    limits(max_buckets: 2)
    expect(ObjectStorageBucket.free_team_limit_reached?(team)).to be false
  end

  it "fixes a free bucket's quota at max_total_gb" do
    limits(free: true, max_total_gb: 1)
    app = create(:app_record, team: team)
    expect(ObjectStorage::Provisioner.create!(app).quota_gb).to eq(1)
  end

  it "caps a paid team's quota at max_total_gb" do
    limits(max_total_gb: 5)
    bucket = create(:object_storage_bucket, team: team)
    expect(bucket.quota_error(6)).to eq([ :forbidden, "Your plan allows up to 5 GB of object storage" ])
    expect(bucket.quota_error(5)).to be_nil
  end
end

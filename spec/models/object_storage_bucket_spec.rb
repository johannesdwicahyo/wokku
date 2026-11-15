require "rails_helper"

RSpec.describe ObjectStorageBucket do
  it "derives the bucket name from the random tail of the app id (not the UUIDv7 timestamp)" do
    app = build_stubbed(:app_record, id: "01a1dec8-3b54-71db-8a2f-0123456789ab")
    expect(described_class.bucket_name_for(app)).to eq("wk-0123456789ab")
  end

  it "reports used_gb and encrypts the secret" do
    b = create(:object_storage_bucket, used_bytes: 1024**3 * 3 / 2)
    expect(b.used_gb).to eq(1.5)
    expect(b.reload.secret_key).to be_present
    expect(described_class.connection.select_value("SELECT secret_key FROM object_storage_buckets WHERE id = '#{b.id}'")).not_to eq(b.secret_key)
  end

  it "nullifies app_record_id when the app is destroyed" do
    b = create(:object_storage_bucket)
    b.app_record.destroy!
    expect(b.reload.app_record_id).to be_nil
  end

  it "validates status and quota" do
    expect(build(:object_storage_bucket, status: "nope")).not_to be_valid
    expect(build(:object_storage_bucket, quota_gb: 0)).not_to be_valid
  end

  it "free_team? follows the team's plan" do
    b = create(:object_storage_bucket)
    allow(b.team).to receive(:current_plan).and_return(instance_double(Plan, free?: true))
    expect(b.free_team?).to be true
  end
end

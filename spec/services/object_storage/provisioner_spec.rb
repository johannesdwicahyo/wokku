require "rails_helper"

RSpec.describe ObjectStorage::Provisioner do
  let(:client) { instance_double(ObjectStorage::Client) }
  let(:app) { create(:app_record) }
  let(:endpoint) { "https://s3.example.test" }
  let(:keys) { %w[S3_ENDPOINT S3_REGION S3_BUCKET S3_ACCESS_KEY_ID S3_SECRET_ACCESS_KEY S3_FORCE_PATH_STYLE AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_REGION AWS_ENDPOINT_URL_S3] }

  before do
    allow(Wokku.config).to receive(:object_storage).and_return(endpoint: endpoint, access_key: "a", secret_key: "s")
    allow(ObjectStorage::Client).to receive(:new).and_return(client)
    allow(Apps::Restarter).to receive(:restart)
    allow_any_instance_of(ObjectStorageBucket).to receive(:free_team?).and_return(false)
  end

  describe ".create!" do
    it "makes a provisioning row and enqueues the job, once" do
      expect { @b = described_class.create!(app) }.to have_enqueued_job(ObjectStorage::ProvisionJob)
      expect(@b).to be_provisioning
      expect(@b.quota_gb).to eq(10)
      expect { expect(described_class.create!(app)).to eq(@b) }.not_to change(ObjectStorageBucket, :count)
    end

    it "uses the free quota for free teams" do
      allow_any_instance_of(ObjectStorageBucket).to receive(:free_team?).and_return(true)
      expect(described_class.create!(app).quota_gb).to eq(1)
    end
  end

  describe ".provision!" do
    let(:bucket) { described_class.create!(app) }

    it "calls the client in order, writes env, restarts, activates" do
      expect(client).to receive(:create_bucket).with(bucket.name).ordered
      expect(client).to receive(:add_user).with(bucket.access_key, bucket.secret_key).ordered
      expect(client).to receive(:put_policy).with(bucket.name, bucket.name).ordered
      expect(client).to receive(:attach_policy).with(bucket.name, bucket.access_key).ordered
      expect(client).to receive(:set_quota).with(bucket.name, 10).ordered
      described_class.provision!(bucket)
      env = app.env_vars.pluck(:key, :value).to_h
      expect(env.keys).to match_array(keys)
      expect(env).to include("S3_ENDPOINT" => endpoint, "S3_BUCKET" => bucket.name, "S3_REGION" => "us-east-1",
        "S3_FORCE_PATH_STYLE" => "true", "AWS_ENDPOINT_URL_S3" => endpoint, "AWS_ACCESS_KEY_ID" => bucket.access_key,
        "S3_SECRET_ACCESS_KEY" => bucket.secret_key)
      expect(Apps::Restarter).to have_received(:restart).with(app)
      expect(bucket.reload).to be_active
    end

    it "marks failed with no env change, no restart, and re-raises" do
      allow(client).to receive(:create_bucket)
      allow(client).to receive(:add_user).and_raise(ObjectStorage::Error, "boom")
      expect { described_class.provision!(bucket) }.to raise_error(ObjectStorage::Error)
      expect(bucket.reload).to be_failed
      expect(bucket.last_error).to eq("boom")
      expect(app.env_vars.count).to eq(0)
      expect(Apps::Restarter).not_to have_received(:restart)
    end
  end

  describe ".resize!" do
    let(:bucket) { create(:object_storage_bucket, app_record: app) }

    it "sets the quota" do
      expect(client).to receive(:set_quota).with(bucket.name, 50)
      described_class.resize!(bucket, 50)
      expect(bucket.reload.quota_gb).to eq(50)
    end

    it "rejects > max and free-team resizes" do
      expect { described_class.resize!(bucket, 2000) }.to raise_error(ArgumentError)
      allow(bucket).to receive(:free_team?).and_return(true)
      expect { described_class.resize!(bucket, 5) }.to raise_error(ArgumentError)
    end
  end

  describe ".rotate!" do
    it "swaps keys, restarts, then removes the old user" do
      bucket = create(:object_storage_bucket, app_record: app)
      old = bucket.access_key
      expect(client).to receive(:add_user).ordered
      expect(client).to receive(:attach_policy).ordered
      expect(Apps::Restarter).to receive(:restart).ordered
      expect(client).to receive(:remove_user).with(old).ordered
      described_class.rotate!(bucket)
      expect(bucket.reload.access_key).not_to eq(old)
      expect(app.env_vars.find_by(key: "S3_ACCESS_KEY_ID").value).to eq(bucket.access_key)
    end
  end

  describe ".destroy!" do
    let(:bucket) { create(:object_storage_bucket, app_record: app) }

    it "unsets env, restarts, deletes remote + row" do
      Apps::EnvWriter.set(app, "S3_BUCKET" => "x")
      expect(client).to receive(:remove_user).with(bucket.access_key)
      expect(client).to receive(:remove_policy).with(bucket.name)
      expect(client).to receive(:delete_bucket!).with(bucket.name)
      described_class.destroy!(bucket)
      expect(app.env_vars.count).to eq(0)
      expect(Apps::Restarter).to have_received(:restart).with(app)
      expect(ObjectStorageBucket.exists?(bucket.id)).to be false
    end

    it "skips env/restart when the app is gone" do
      bucket.app_record.destroy!
      allow(client).to receive_messages(remove_user: true, remove_policy: true, delete_bucket!: true)
      described_class.destroy!(bucket.reload)
      expect(Apps::Restarter).not_to have_received(:restart)
      expect(ObjectStorageBucket.exists?(bucket.id)).to be false
    end

    it "goes to deleting and re-raises on client errors" do
      allow(client).to receive(:remove_user).and_raise(ObjectStorage::Error, "down")
      expect { described_class.destroy!(bucket) }.to raise_error(ObjectStorage::Error)
      expect(bucket.reload).to be_deleting
      expect(bucket.last_error).to eq("down")
    end
  end
end

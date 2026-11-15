require "rails_helper"

RSpec.describe "object storage jobs" do
  let(:bucket) { create(:object_storage_bucket) }

  it "ProvisionJob delegates to the provisioner" do
    expect(ObjectStorage::Provisioner).to receive(:provision!).with(bucket)
    ObjectStorage::ProvisionJob.perform_now(bucket.id)
  end

  it "ProvisionJob retries ObjectStorage::Error" do
    allow(ObjectStorage::Provisioner).to receive(:provision!).and_raise(ObjectStorage::Error, "x")
    expect { ObjectStorage::ProvisionJob.perform_now(bucket.id) }.to have_enqueued_job(ObjectStorage::ProvisionJob)
  end

  it "ProvisionJob is a no-op for a missing bucket" do
    expect { ObjectStorage::ProvisionJob.perform_now(SecureRandom.uuid) }.not_to raise_error
  end

  it "DeprovisionJob delegates to destroy!" do
    expect(ObjectStorage::Provisioner).to receive(:destroy!).with(bucket)
    ObjectStorage::DeprovisionJob.perform_now(bucket.id)
  end

  describe ObjectStorage::UsageRefreshJob do
    let(:client) { instance_double(ObjectStorage::Client) }
    before do
      allow(Wokku.config).to receive(:object_storage?).and_return(true)
      allow(ObjectStorage::Client).to receive(:new).and_return(client)
    end

    it "updates usage and mails once at 80%" do
      allow(client).to receive(:usage).and_return(bucket.name => (8.5 * 1024**3).to_i)
      expect { described_class.perform_now }.to have_enqueued_mail(ObjectStorageMailer, :near_quota).once
      expect(bucket.reload.used_bytes).to eq((8.5 * 1024**3).to_i)
      expect(bucket.used_at).to be_present
      expect(bucket.warned_at).to be_present
      expect { described_class.perform_now }.not_to have_enqueued_mail(ObjectStorageMailer, :near_quota)
    end

    it "keeps the previous usage and warning for buckets missing from the usage report" do
      warned = 1.hour.ago.change(usec: 0)
      bucket.update!(used_bytes: 9 * 1024**3, warned_at: warned)
      allow(client).to receive(:usage).and_return({})
      described_class.perform_now
      expect(bucket.reload.used_bytes).to eq(9 * 1024**3)
      expect(bucket.warned_at).to eq(warned)
    end

    it "clears the warning once usage drops below 80%" do
      bucket.update!(used_bytes: 9 * 1024**3, warned_at: Time.current)
      allow(client).to receive(:usage).and_return(bucket.name => 1024)
      described_class.perform_now
      expect(bucket.reload.used_bytes).to eq(1024)
      expect(bucket.warned_at).to be_nil
    end

    it "re-enqueues deprovisioning for deleting and orphaned buckets, not live ones" do
      allow(client).to receive(:usage).and_return({})
      deleting = create(:object_storage_bucket, status: "deleting")
      orphan = create(:object_storage_bucket)
      orphan.update_column(:app_record_id, nil)
      bucket # active, attached
      described_class.perform_now
      expect(ObjectStorage::DeprovisionJob).to have_been_enqueued.with(deleting.id)
      expect(ObjectStorage::DeprovisionJob).to have_been_enqueued.with(orphan.id)
      expect(ObjectStorage::DeprovisionJob).not_to have_been_enqueued.with(bucket.id)
    end

    it "still sweeps when the usage call fails" do
      deleting = create(:object_storage_bucket, status: "deleting")
      allow(client).to receive(:usage).and_raise(ObjectStorage::Error, "down")
      expect { described_class.perform_now }.to raise_error(ObjectStorage::Error)
      expect(ObjectStorage::DeprovisionJob).to have_been_enqueued.with(deleting.id)
    end

    it "skips when object storage is unconfigured" do
      allow(Wokku.config).to receive(:object_storage?).and_return(false)
      expect(ObjectStorage::Client).not_to receive(:new)
      create(:object_storage_bucket, status: "deleting")
      expect { described_class.perform_now }.not_to have_enqueued_job(ObjectStorage::DeprovisionJob)
    end
  end
end

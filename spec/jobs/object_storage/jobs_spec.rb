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

    it "treats missing buckets as 0 and clears the warning below 80%" do
      bucket.update!(used_bytes: 9 * 1024**3, warned_at: Time.current)
      allow(client).to receive(:usage).and_return({})
      described_class.perform_now
      expect(bucket.reload.used_bytes).to eq(0)
      expect(bucket.warned_at).to be_nil
    end

    it "skips when object storage is unconfigured" do
      allow(Wokku.config).to receive(:object_storage?).and_return(false)
      expect(ObjectStorage::Client).not_to receive(:new)
      described_class.perform_now
    end
  end
end

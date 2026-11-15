# frozen_string_literal: true

require "rails_helper"

RSpec.describe Apps::Destroyer, "object storage bucket" do
  let(:app_record) { create(:app_record, server: create(:server)) }
  let!(:bucket) { create(:object_storage_bucket, app_record: app_record) }

  before do
    allow(Wokku.config.dns_provider).to receive(:delete_app_record)
    allow(Git::BareRepo).to receive(:new).and_return(instance_double(Git::BareRepo, remove!: true))
  end

  it "destroys the bucket after the app row is gone, without touching env/restart" do
    client = instance_double(ObjectStorage::Client, remove_user: true, remove_policy: true, delete_bucket!: true)
    allow(ObjectStorage::Client).to receive(:new).and_return(client)
    expect(Apps::EnvWriter).not_to receive(:unset)
    expect(Apps::Restarter).not_to receive(:restart)

    result = described_class.call(app_record)

    expect(client).to have_received(:delete_bucket!).with(bucket.name)
    expect(ObjectStorageBucket.where(id: bucket.id)).not_to exist
    expect(result.warnings).to be_empty
  end

  it "captures a client error in the Result, marks the bucket deleting and enqueues a retry" do
    client = instance_double(ObjectStorage::Client, remove_user: true, remove_policy: true)
    allow(client).to receive(:delete_bucket!).and_raise(ObjectStorage::Error, "rustfs down")
    allow(ObjectStorage::Client).to receive(:new).and_return(client)

    result = nil
    expect { result = described_class.call(app_record) }
      .to have_enqueued_job(ObjectStorage::DeprovisionJob).with(bucket.id)

    expect(AppRecord.where(id: app_record.id)).not_to exist
    expect(result.warnings.join).to include("rustfs down")
    expect(bucket.reload).to have_attributes(status: "deleting", app_record_id: nil)
  end
end

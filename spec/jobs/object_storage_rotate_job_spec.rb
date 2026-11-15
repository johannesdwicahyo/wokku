# frozen_string_literal: true

require "rails_helper"

RSpec.describe ObjectStorage::RotateJob do
  it "rotates an active bucket" do
    b = create(:object_storage_bucket)
    expect(ObjectStorage::Provisioner).to receive(:rotate!).with(b)
    described_class.perform_now(b.id)
  end

  it "skips non-active or missing buckets" do
    b = create(:object_storage_bucket, status: "deleting")
    expect(ObjectStorage::Provisioner).not_to receive(:rotate!)
    described_class.perform_now(b.id)
    described_class.perform_now(SecureRandom.uuid)
  end
end

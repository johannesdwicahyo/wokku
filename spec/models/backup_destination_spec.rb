# frozen_string_literal: true

require "rails_helper"
require "aws-sdk-s3"

# No network: Aws::S3::Client / Aws::S3::Presigner are stubbed throughout,
# mirroring DeployArchiveStore's spec idiom (spec/services/deploy_archive_store_spec.rb).
RSpec.describe BackupDestination do
  let(:server) { create(:server) }
  let(:destination) do
    server.create_backup_destination!(
      provider: "s3", bucket: "my-bucket", region: "us-east-1",
      access_key_id: "AKID", secret_access_key: "SECRET"
    )
  end

  let(:s3) { instance_double(Aws::S3::Client) }
  let(:signer) { instance_double(Aws::S3::Presigner) }

  before do
    allow(Aws::S3::Client).to receive(:new).and_return(s3)
    allow(Aws::S3::Presigner).to receive(:new).with(client: s3).and_return(signer)
  end

  describe "#s3_presigned_put" do
    it "builds a PUT presigned URL scoped to the bucket + key with a 1 hour default expiry" do
      expect(signer).to receive(:presigned_url)
        .with(:put_object, bucket: "my-bucket", key: "dbs/foo/backup.sql.gz", expires_in: 3600)
        .and_return("https://signed.example/put")

      expect(destination.s3_presigned_put("dbs/foo/backup.sql.gz")).to eq("https://signed.example/put")
    end

    it "honors a custom expires_in" do
      expect(signer).to receive(:presigned_url).with(:put_object, hash_including(expires_in: 60))
      destination.s3_presigned_put("k", expires_in: 60)
    end
  end
end

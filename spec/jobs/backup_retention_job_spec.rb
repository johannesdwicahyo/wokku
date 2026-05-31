# frozen_string_literal: true

require "rails_helper"

RSpec.describe BackupRetentionJob, type: :job do
  it "can be enqueued" do
    expect { described_class.perform_later }.to have_enqueued_job(described_class)
  end

  it "does nothing when no enabled backup destinations" do
    BackupDestination.update_all(enabled: false) if BackupDestination.exists?
    expect { described_class.perform_now }.not_to raise_error
  end

  it "deletes expired backups from S3 and destroys records" do
    server = servers(:one)
    destination = BackupDestination.create!(
      server: server, bucket: "test-bucket", region: "us-east-1",
      access_key_id: "AKID", secret_access_key: "secret",
      enabled: true, retention_days: 7, path_prefix: "backups"
    )
    db = database_services(:one)
    old_backup = db.backups.create!(
      backup_destination: destination,
      status: "completed",
      s3_key: "backups/postgres/pg-main/old.gz",
      started_at: 10.days.ago,
      completed_at: 10.days.ago
    )
    old_backup.update_columns(created_at: 10.days.ago, updated_at: 10.days.ago)

    fake_s3 = double("s3")
    allow(fake_s3).to receive(:delete_object).and_return(true)
    allow_any_instance_of(BackupDestination).to receive(:s3_client).and_return(fake_s3)

    expect { described_class.perform_now }.to change { Backup.count }.by(-1)
    expect(Backup.find_by(id: old_backup.id)).to be_nil
  end
end

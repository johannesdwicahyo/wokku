require "test_helper"

class BackupRetentionJobTest < ActiveJob::TestCase
  test "can be enqueued" do
    assert_enqueued_jobs 1 do
      BackupRetentionJob.perform_later
    end
  end

  test "does nothing when no enabled backup destinations" do
    # Ensure no enabled backup destinations exist
    BackupDestination.update_all(enabled: false) if BackupDestination.exists?

    assert_nothing_raised do
      BackupRetentionJob.perform_now
    end
  end

  test "deletes expired backups from S3 and destroys records" do
    server = servers(:one)

    destination = BackupDestination.create!(
      server: server,
      bucket: "test-bucket",
      region: "us-east-1",
      access_key_id: "AKID",
      secret_access_key: "secret",
      enabled: true,
      retention_days: 7,
      path_prefix: "backups"
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

    # Stub BackupDestination#s3_client on the class level to avoid real AWS calls
    BackupDestination.class_eval do
      define_method(:s3_client) do
        mock = Object.new
        mock.define_singleton_method(:delete_object) { |**_kwargs| true }
        mock
      end
    end

    assert_difference "Backup.count", -1 do
      BackupRetentionJob.perform_now
    end

    assert_nil Backup.find_by(id: old_backup.id)
  ensure
    BackupDestination.class_eval do
      remove_method :s3_client rescue nil
    end
    destination&.destroy
  end
end

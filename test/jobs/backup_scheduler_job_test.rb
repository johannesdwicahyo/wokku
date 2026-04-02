require "test_helper"

class BackupSchedulerJobTest < ActiveJob::TestCase
  test "can be enqueued" do
    assert_enqueued_jobs 1 do
      BackupSchedulerJob.perform_later
    end
  end

  test "enqueues BackupJob for each running database with a backup destination" do
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

    db = DatabaseService.create!(
      server: server,
      service_type: "postgres",
      name: "pg-scheduler-test",
      status: :running
    )

    assert_enqueued_with(job: BackupJob) do
      BackupSchedulerJob.perform_now
    end
  ensure
    db&.destroy
    destination&.destroy
  end

  test "does not enqueue BackupJob when no enabled backup destinations" do
    # No backup destinations — no jobs enqueued
    BackupDestination.where(enabled: true).destroy_all

    assert_no_enqueued_jobs only: BackupJob do
      BackupSchedulerJob.perform_now
    end
  end
end

require "test_helper"

class BackupJobTest < ActiveJob::TestCase
  setup do
    @db = database_services(:one)
  end

  test "can be enqueued" do
    assert_enqueued_jobs 1 do
      BackupJob.perform_later(@db.id)
    end
  end

  test "calls BackupService.perform!" do
    performed = false

    BackupService.class_eval do
      alias_method :original_initialize, :initialize
      define_method(:initialize) { |_db| }
      define_method(:perform!) { performed = true }
    end

    BackupJob.perform_now(@db.id)
    assert performed
  ensure
    BackupService.class_eval do
      alias_method :initialize, :original_initialize
      remove_method :original_initialize
      remove_method :perform!
    end
  end

  test "logs error but does not raise when BackupService fails" do
    BackupService.class_eval do
      alias_method :original_initialize, :initialize
      define_method(:initialize) { |_db| }
      define_method(:perform!) { raise "S3 connection refused" }
    end

    assert_nothing_raised do
      BackupJob.perform_now(@db.id)
    end
  ensure
    BackupService.class_eval do
      alias_method :initialize, :original_initialize
      remove_method :original_initialize
      remove_method :perform!
    end
  end
end

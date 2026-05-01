require "test_helper"

class BackupTest < ActiveSupport::TestCase
  test "size_human formats bytes correctly" do
    backup = Backup.new(size_bytes: 1024)
    assert_equal "1.0 KB", backup.size_human

    backup.size_bytes = 5 * 1024 * 1024
    assert_equal "5.0 MB", backup.size_human
  end

  test "expired? checks retention days" do
    dest = BackupDestination.new(retention_days: 7)
    backup = Backup.new(backup_destination: dest, created_at: 8.days.ago)
    assert backup.expired?

    backup.created_at = 3.days.ago
    assert_not backup.expired?
  end
end

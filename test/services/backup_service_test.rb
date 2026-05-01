require "test_helper"

class BackupServiceTest < ActiveSupport::TestCase
  test "export_command returns correct command for postgres" do
    db = DatabaseService.new(name: "my-db", service_type: "postgres")
    service = BackupService.new(db)
    assert_equal "postgres:export my-db", service.send(:export_command)
  end

  test "export_command returns correct command for mysql" do
    db = DatabaseService.new(name: "my-db", service_type: "mysql")
    service = BackupService.new(db)
    assert_equal "mysql:export my-db", service.send(:export_command)
  end

  test "s3_key generates timestamped path" do
    db = DatabaseService.new(name: "my-db", service_type: "postgres")
    service = BackupService.new(db)
    key = service.send(:generate_s3_key, "wokku-backups")
    assert_match %r{wokku-backups/postgres/my-db/\d{4}-\d{2}-\d{2}}, key
  end
end

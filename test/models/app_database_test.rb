require "test_helper"

class AppDatabaseTest < ActiveSupport::TestCase
  test "app_record and database_service combination is unique" do
    existing = app_databases(:one)
    duplicate = AppDatabase.new(
      app_record: existing.app_record,
      database_service: existing.database_service,
      alias_name: "OTHER"
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:app_record_id], "has already been taken"
  end

  test "alias_name is required" do
    ad = AppDatabase.new(app_record: app_records(:one), database_service: database_services(:two))
    assert_not ad.valid?
    assert_includes ad.errors[:alias_name], "can't be blank"
  end
end

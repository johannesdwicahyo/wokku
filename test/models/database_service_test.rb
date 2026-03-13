require "test_helper"

class DatabaseServiceTest < ActiveSupport::TestCase
  test "name is unique per server" do
    existing = database_services(:one)
    duplicate = DatabaseService.new(server: existing.server, name: existing.name, service_type: "postgres")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
  end

  test "service_type must be a valid type" do
    ds = DatabaseService.new(server: servers(:one), name: "test-db", service_type: "invalid")
    assert_not ds.valid?
    assert_includes ds.errors[:service_type], "is not included in the list"
  end

  test "enum status values" do
    ds = database_services(:one)
    assert ds.running?
  end
end

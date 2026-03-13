require "test_helper"

class DomainTest < ActiveSupport::TestCase
  test "hostname must be unique" do
    domain = domains(:one)
    duplicate = Domain.new(app_record: domain.app_record, hostname: domain.hostname)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:hostname], "has already been taken"
  end

  test "hostname is required" do
    domain = Domain.new(app_record: app_records(:one))
    assert_not domain.valid?
    assert_includes domain.errors[:hostname], "can't be blank"
  end
end

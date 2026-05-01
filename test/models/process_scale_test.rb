require "test_helper"

class ProcessScaleTest < ActiveSupport::TestCase
  test "process_type is unique per app_record" do
    existing = process_scales(:one)
    duplicate = ProcessScale.new(app_record: existing.app_record, process_type: existing.process_type)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:process_type], "has already been taken"
  end

  test "count must be non-negative" do
    ps = ProcessScale.new(app_record: app_records(:one), process_type: "clock", count: -1)
    assert_not ps.valid?
    assert_includes ps.errors[:count], "must be greater than or equal to 0"
  end
end

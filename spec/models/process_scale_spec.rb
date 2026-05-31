require "rails_helper"

RSpec.describe ProcessScale do
  it "process_type is unique per app_record" do
    existing = process_scales(:one)
    duplicate = ProcessScale.new(app_record: existing.app_record, process_type: existing.process_type)
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:process_type]).to include("has already been taken")
  end

  it "count must be non-negative" do
    ps = ProcessScale.new(app_record: app_records(:one), process_type: "clock", count: -1)
    expect(ps).not_to be_valid
    expect(ps.errors[:count]).to include("must be greater than or equal to 0")
  end
end

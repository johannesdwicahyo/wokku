require "rails_helper"

RSpec.describe Domain do
  it "hostname must be unique" do
    domain = domains(:one)
    duplicate = Domain.new(app_record: domain.app_record, hostname: domain.hostname)
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:hostname]).to include("has already been taken")
  end

  it "hostname is required" do
    domain = Domain.new(app_record: app_records(:one))
    expect(domain).not_to be_valid
    expect(domain.errors[:hostname]).to include("can't be blank")
  end
end

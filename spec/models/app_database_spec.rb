require "rails_helper"

RSpec.describe AppDatabase do
  it "app_record and database_service combination is unique" do
    existing = app_databases(:one)
    duplicate = AppDatabase.new(
      app_record: existing.app_record,
      database_service: existing.database_service,
      alias_name: "OTHER"
    )
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:app_record_id]).to include("has already been taken")
  end

  it "alias_name is required" do
    ad = AppDatabase.new(app_record: app_records(:one), database_service: database_services(:two))
    expect(ad).not_to be_valid
    expect(ad.errors[:alias_name]).to include("can't be blank")
  end
end

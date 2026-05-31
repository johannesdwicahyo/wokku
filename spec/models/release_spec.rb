require "rails_helper"

RSpec.describe Release do
  it "auto-increments version on create" do
    app = app_records(:one)
    release = Release.create!(app_record: app, description: "test release")
    expect(release.version).to be > 0
  end

  it "version is unique per app_record" do
    release = releases(:one)
    duplicate = Release.new(app_record: release.app_record, version: release.version)
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:version]).to include("has already been taken")
  end
end

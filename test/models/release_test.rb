require "test_helper"

class ReleaseTest < ActiveSupport::TestCase
  test "auto-increments version on create" do
    app = app_records(:one)
    release = Release.create!(app_record: app, description: "test release")
    assert release.version > 0
  end

  test "version is unique per app_record" do
    release = releases(:one)
    duplicate = Release.new(app_record: release.app_record, version: release.version)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:version], "has already been taken"
  end
end

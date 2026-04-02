require "test_helper"

class DeviceTokenTest < ActiveSupport::TestCase
  # --- Validations ---

  test "valid with token, platform, and user" do
    dt = DeviceToken.new(token: "unique-token-xyz", platform: "ios", user: users(:one))
    assert dt.valid?
  end

  test "invalid without token" do
    dt = DeviceToken.new(platform: "ios", user: users(:one))
    assert_not dt.valid?
    assert_includes dt.errors[:token], "can't be blank"
  end

  test "invalid with duplicate token" do
    existing = device_tokens(:one)
    dt = DeviceToken.new(token: existing.token, platform: "android", user: users(:two))
    assert_not dt.valid?
    assert_includes dt.errors[:token], "has already been taken"
  end

  test "invalid without platform" do
    dt = DeviceToken.new(token: "some-token-abc", user: users(:one))
    assert_not dt.valid?
    assert_includes dt.errors[:platform], "can't be blank"
  end

  test "invalid with unsupported platform" do
    dt = DeviceToken.new(token: "some-token-abc", platform: "windows", user: users(:one))
    assert_not dt.valid?
    assert_includes dt.errors[:platform], "is not included in the list"
  end

  test "valid for ios platform" do
    dt = DeviceToken.new(token: "ios-token-test", platform: "ios", user: users(:one))
    assert dt.valid?
  end

  test "valid for android platform" do
    dt = DeviceToken.new(token: "android-token-test", platform: "android", user: users(:two))
    assert dt.valid?
  end

  # --- Associations ---

  test "belongs to user" do
    dt = device_tokens(:one)
    assert_equal users(:one), dt.user
  end

  test "user has many device_tokens" do
    user = users(:one)
    assert_includes user.device_tokens, device_tokens(:one)
  end

  test "destroying user destroys associated device_tokens" do
    user = User.create!(email: "token-owner@example.com", password: "password123456")
    DeviceToken.create!(token: "dependent-token-001", platform: "ios", user: user)
    assert_difference "DeviceToken.count", -1 do
      user.destroy
    end
  end
end

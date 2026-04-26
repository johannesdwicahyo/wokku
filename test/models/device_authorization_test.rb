require "test_helper"

class DeviceAuthorizationTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "device-test@example.com", password: "password123456")
    Rails.cache.clear
  end

  test "start! creates pending record with codes and expiry" do
    auth = DeviceAuthorization.start!
    assert auth.persisted?
    assert_equal "pending", auth.status
    assert auth.device_code.present?
    assert_match /\A[A-Z]{4}-[A-Z]{4}\z/, auth.user_code
    assert auth.expires_at > Time.current
  end

  test "user codes are unique" do
    a = DeviceAuthorization.start!
    b = DeviceAuthorization.start!
    refute_equal a.user_code, b.user_code
  end

  test "approve! mints token, links user, persists encrypted plain token" do
    auth = DeviceAuthorization.start!
    assert auth.approve!(@user)
    auth.reload
    assert_equal "approved", auth.status
    assert_equal @user, auth.user
    assert auth.api_token.present?
    assert auth.plain_token_payload.present?
    assert_equal 64, auth.plain_token_payload.length
  end

  test "consume_plain_token! returns and clears once" do
    auth = DeviceAuthorization.start!
    auth.approve!(@user)
    auth.reload
    token = auth.consume_plain_token!
    assert_equal 64, token.length
    assert_nil auth.reload.consume_plain_token!
  end

  test "approve! returns false if expired" do
    auth = DeviceAuthorization.start!
    auth.update_column(:expires_at, 1.minute.ago)
    refute auth.approve!(@user)
  end

  test "approve! returns false if already approved" do
    auth = DeviceAuthorization.start!
    auth.approve!(@user)
    refute auth.approve!(@user)
  end

  test "deny! marks denied" do
    auth = DeviceAuthorization.start!
    assert auth.deny!
    assert auth.reload.denied?
  end

  test "deny! returns false if expired" do
    auth = DeviceAuthorization.start!
    auth.update_column(:expires_at, 1.minute.ago)
    refute auth.deny!
  end

  test "expired? reflects expires_at" do
    auth = DeviceAuthorization.start!
    refute auth.expired?
    auth.update_column(:expires_at, 1.second.ago)
    assert auth.expired?
  end

  test "pending? false after expiry" do
    auth = DeviceAuthorization.start!
    auth.update_column(:expires_at, 1.second.ago)
    refute auth.pending?
  end

  test "active scope excludes expired" do
    fresh = DeviceAuthorization.start!
    stale = DeviceAuthorization.start!
    stale.update_column(:expires_at, 1.minute.ago)
    ids = DeviceAuthorization.active.pluck(:id)
    assert_includes ids, fresh.id
    refute_includes ids, stale.id
  end

  test "touch_polled! sets timestamp" do
    auth = DeviceAuthorization.start!
    assert_nil auth.last_polled_at
    auth.touch_polled!
    assert auth.reload.last_polled_at
  end
end

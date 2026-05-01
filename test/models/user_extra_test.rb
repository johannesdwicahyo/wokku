require "test_helper"

class UserExtraTest < ActiveSupport::TestCase
  test "non-admin email cannot be promoted to admin role" do
    user = users(:one)
    user.role = :admin
    assert_not user.valid?
    assert_match(/restricted/, user.errors[:role].join)
  end

  test "only one admin account allowed" do
    # admin fixture exists with admin@wokku.cloud. Try creating another.
    dup = User.new(email: "admin@wokku.cloud", password: "password123456", role: :admin)
    assert_not dup.valid?
  end

  test "non-admin email matching reserved admin email is blocked" do
    user = User.new(email: User::ADMIN_EMAIL, password: "password123456", role: :member)
    assert_not user.valid?
    assert_includes user.errors[:email], "is reserved"
  end

  test "currency cannot change while user has active paid resources" do
    user = users(:one)
    ResourceUsage.create!(
      user: user, resource_type: "container", resource_id_ref: "AppRecord:1",
      tier_name: "basic", price_cents_per_hour: 1.0, started_at: 1.day.ago
    )
    user.update(currency: "idr")
    assert_match(/cannot be changed/, user.errors[:currency].join)
  end

  test "from_omniauth links existing admin on first OAuth attempt" do
    admin = users(:admin)
    admin.update_columns(provider: nil, uid: nil)
    auth = OpenStruct.new(
      provider: "google_oauth2", uid: "goog-admin",
      info: OpenStruct.new(email: User::ADMIN_EMAIL, name: "Admin", image: "https://x")
    )
    result = User.from_omniauth(auth)
    assert_equal admin, result
    assert_equal "google_oauth2", admin.reload.provider
    assert_equal "goog-admin", admin.uid
  end

  test "from_omniauth returns unpersisted user when admin email has no seed" do
    users(:admin).destroy!
    auth = OpenStruct.new(
      provider: "github", uid: "u1",
      info: OpenStruct.new(email: User::ADMIN_EMAIL, name: "X", image: "")
    )
    result = User.from_omniauth(auth)
    assert_not result.persisted?
  end

  test "estimated_monthly_cost_cents sums billable usage for the month" do
    user = users(:one)
    ResourceUsage.create!(
      user: user, resource_type: "container", resource_id_ref: "AppRecord:1",
      tier_name: "basic", price_cents_per_hour: 1.0, started_at: Time.current.beginning_of_month
    )
    assert user.estimated_monthly_cost_cents > 0
  end

  test "active_resource_usages scopes to active" do
    user = users(:one)
    ResourceUsage.create!(
      user: user, resource_type: "container", resource_id_ref: "AppRecord:1",
      tier_name: "basic", price_cents_per_hour: 1.0, started_at: 1.day.ago
    )
    assert user.active_resource_usages.any?
  end
end

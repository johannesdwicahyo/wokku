require "test_helper"

class UserTest < ActiveSupport::TestCase
  # --- Validations (via Devise :validatable) ---

  test "valid user with email and password" do
    user = User.new(email: "test@example.com", password: "password123456")
    assert user.valid?
  end

  test "invalid without email" do
    user = User.new(password: "password123456")
    assert_not user.valid?
    assert_includes user.errors[:email], "can't be blank"
  end

  test "invalid with duplicate email" do
    existing = users(:one)
    user = User.new(email: existing.email, password: "password123456")
    assert_not user.valid?
    assert_includes user.errors[:email], "has already been taken"
  end

  test "invalid with short password" do
    user = User.new(email: "short@example.com", password: "abc")
    assert_not user.valid?
  end

  # --- Role enum ---

  test "default role is member" do
    user = User.new(email: "test@example.com", password: "password123456")
    assert_equal "member", user.role
  end

  test "fixture one has member role" do
    assert users(:one).member?
    assert_not users(:one).admin?
  end

  test "fixture two has admin role" do
    assert users(:two).admin?
  end

  test "role enum has member and admin values" do
    assert_equal({ "member" => 0, "admin" => 1 }, User.roles)
  end

  # --- two_factor_enabled? ---

  test "two_factor_enabled? returns false when otp_required_for_login is false" do
    user = users(:one)
    user.otp_required_for_login = false
    assert_not user.two_factor_enabled?
  end

  test "two_factor_enabled? returns true when otp_required_for_login is true" do
    user = users(:one)
    user.otp_required_for_login = true
    assert user.two_factor_enabled?
  end

  # --- Lockable ---

  test "tracks failed_attempts and locked_at columns" do
    user = users(:one)
    assert_respond_to user, :failed_attempts
    assert_respond_to user, :locked_at
  end

  test "lock_access! sets locked_at" do
    user = User.create!(email: "lockable@example.com", password: "password123456")
    user.lock_access!
    assert_not_nil user.reload.locked_at
  end

  test "unlock_access! clears locked_at" do
    user = User.create!(email: "unlockable@example.com", password: "password123456")
    user.lock_access!
    user.unlock_access!
    assert_nil user.reload.locked_at
  end

  # --- Associations ---

  test "has many api_tokens" do
    assert_respond_to users(:one), :api_tokens
  end

  test "has many ssh_public_keys" do
    assert_respond_to users(:one), :ssh_public_keys
  end

  test "has many team_memberships" do
    assert_respond_to users(:one), :team_memberships
  end

  test "has many teams through team_memberships" do
    assert_respond_to users(:one), :teams
  end

  test "has many device_tokens" do
    assert_respond_to users(:one), :device_tokens
  end

  # --- current_plan ---

  test "current_plan returns nil" do
    assert_nil users(:one).current_plan
  end
end

require "test_helper"

class SubscriptionTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "sub-test@example.com", password: "password123456")
    @plan = plans(:hobby)
  end

  test "valid subscription" do
    sub = Subscription.new(user: @user, plan: @plan, status: :active)
    assert sub.valid?
  end

  test "default status is active" do
    sub = Subscription.new(user: @user, plan: @plan)
    assert_equal "active", sub.status
  end

  test "current scope returns active and trialing" do
    active = Subscription.create!(user: @user, plan: @plan, status: :active)
    canceled = Subscription.create!(user: @user, plan: plans(:free), status: :canceled)

    current = Subscription.current
    assert_includes current, active
    assert_not_includes current, canceled
  end

  test "enum statuses" do
    sub = Subscription.new(user: @user, plan: @plan)
    sub.status = :past_due
    assert sub.past_due?
    sub.status = :canceled
    assert sub.canceled?
    sub.status = :trialing
    assert sub.trialing?
  end
end

require "test_helper"

class UsageEventTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "usage-test@example.com", password: "password123456")
  end

  test "valid usage event" do
    event = UsageEvent.new(user: @user, event_type: "deploy")
    assert event.valid?
  end

  test "requires event_type" do
    event = UsageEvent.new(user: @user)
    assert_not event.valid?
    assert_includes event.errors[:event_type], "can't be blank"
  end

  test "app_record is optional" do
    event = UsageEvent.new(user: @user, event_type: "login")
    assert event.valid?
  end
end

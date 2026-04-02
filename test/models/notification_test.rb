require "test_helper"

class NotificationTest < ActiveSupport::TestCase
  test "channel enum values" do
    notification = notifications(:one)
    assert notification.email?
  end

  test "events is required" do
    n = Notification.new(team: teams(:one), channel: :email)
    assert_not n.valid?
    assert_includes n.errors[:events], "can't be blank"
  end

  test "app_record is optional" do
    n = Notification.new(team: teams(:one), channel: :slack, events: [ "deploy.succeeded" ])
    assert n.valid?
  end
end

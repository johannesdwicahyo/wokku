require "test_helper"

class NotificationTest < ActiveSupport::TestCase
  # --- Existing tests ---

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

  # --- Extended tests ---

  test "channel is required" do
    n = Notification.new(team: teams(:one), events: [ "deploy.succeeded" ])
    assert_not n.valid?
    assert_includes n.errors[:channel], "can't be blank"
  end

  test "valid notification with all required fields" do
    n = Notification.new(team: teams(:one), channel: :email, events: [ "deploy.succeeded" ])
    assert n.valid?
  end

  test "channel enum includes all expected values" do
    assert_equal({ "email" => 0, "slack" => 1, "webhook" => 2, "discord" => 3, "telegram" => 4 }, Notification.channels)
  end

  test "fixture one is associated with app_record" do
    n = notifications(:one)
    assert_not_nil n.app_record
    assert_equal app_records(:one), n.app_record
  end

  test "fixture two has no app_record" do
    n = notifications(:two)
    assert_nil n.app_record
  end

  test "fixture two uses slack channel" do
    n = notifications(:two)
    assert n.slack?
  end

  test "belongs to team" do
    n = notifications(:one)
    assert_equal teams(:one), n.team
  end

  test "all channel values are valid" do
    %i[email slack webhook discord telegram].each do |ch|
      n = Notification.new(team: teams(:one), channel: ch, events: [ "deploy.succeeded" ])
      assert n.valid?, "expected channel #{ch} to be valid"
    end
  end
end

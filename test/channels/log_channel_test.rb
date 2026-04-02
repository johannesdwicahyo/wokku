require "test_helper"

class LogChannelTest < ActionCable::Channel::TestCase
  test "raises when subscribing without app_id" do
    stub_connection current_user: users(:one)
    assert_raises(ActiveRecord::RecordNotFound) { subscribe }
  end

  test "raises when subscribing with nonexistent app_id" do
    stub_connection current_user: users(:one)
    assert_raises(ActiveRecord::RecordNotFound) { subscribe(app_id: -999) }
  end

  test "subscribes and streams for valid app" do
    stub_connection current_user: users(:one)
    app = app_records(:one)
    subscribe(app_id: app.id)
    assert subscription.confirmed?
    assert_has_stream_for app
  end
end

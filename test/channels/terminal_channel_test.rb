require "test_helper"

class TerminalChannelTest < ActionCable::Channel::TestCase
  test "rejects subscription without server_id" do
    stub_connection current_user: users(:one)
    subscribe
    assert subscription.rejected?
  end

  test "rejects subscription for unauthorized server" do
    stub_connection current_user: users(:one)
    subscribe(server_id: -1)
    assert subscription.rejected?
  end
end

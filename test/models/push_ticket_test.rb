require "test_helper"

class PushTicketTest < ActiveSupport::TestCase
  setup do
    @user = users(:two)
    @device_token = DeviceToken.create!(user: @user, token: "ExponentPushToken[test-#{SecureRandom.hex(8)}]", platform: "ios")
  end

  test "validates ticket_id presence" do
    ticket = PushTicket.new(device_token: @device_token, ticket_id: nil)
    assert_not ticket.valid?
  end

  test "validates ticket_id uniqueness" do
    PushTicket.create!(device_token: @device_token, ticket_id: "ticket-abc")
    duplicate = PushTicket.new(device_token: @device_token, ticket_id: "ticket-abc")
    assert_not duplicate.valid?
  end

  test "pending scope returns unchecked tickets" do
    PushTicket.create!(device_token: @device_token, ticket_id: "t1", checked_at: Time.current)
    pending = PushTicket.create!(device_token: @device_token, ticket_id: "t2", checked_at: nil)
    assert_includes PushTicket.pending, pending
  end

  test "belongs to device_token" do
    ticket = PushTicket.create!(device_token: @device_token, ticket_id: "t3")
    assert_equal @device_token, ticket.device_token
  end
end

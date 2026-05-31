require "rails_helper"

RSpec.describe PushTicket do
  let(:user) { users(:two) }
  let(:device_token) do
    DeviceToken.create!(user: user, token: "ExponentPushToken[test-#{SecureRandom.hex(8)}]", platform: "ios")
  end

  it "validates ticket_id presence" do
    ticket = PushTicket.new(device_token: device_token, ticket_id: nil)
    expect(ticket).not_to be_valid
  end

  it "validates ticket_id uniqueness" do
    PushTicket.create!(device_token: device_token, ticket_id: "ticket-abc")
    duplicate = PushTicket.new(device_token: device_token, ticket_id: "ticket-abc")
    expect(duplicate).not_to be_valid
  end

  it "pending scope returns unchecked tickets" do
    PushTicket.create!(device_token: device_token, ticket_id: "t1", checked_at: Time.current)
    pending = PushTicket.create!(device_token: device_token, ticket_id: "t2", checked_at: nil)
    expect(PushTicket.pending).to include(pending)
  end

  it "belongs to device_token" do
    ticket = PushTicket.create!(device_token: device_token, ticket_id: "t3")
    expect(ticket.device_token).to eq(device_token)
  end
end

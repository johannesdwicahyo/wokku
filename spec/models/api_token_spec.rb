require "rails_helper"

RSpec.describe ApiToken do
  let(:user) { User.create!(email: "apitoken-test@example.com", password: "password123456") }

  describe ".create_with_token!" do
    it "returns token and plain text" do
      token, plain = ApiToken.create_with_token!(user: user, name: "test")
      expect(token).to be_persisted
      expect(plain.length).to eq(64)
    end
  end

  describe ".find_by_token" do
    it "finds active token" do
      token, plain = ApiToken.create_with_token!(user: user, name: "test")
      expect(ApiToken.find_by_token(plain).id).to eq(token.id)
    end
  end

  describe "#active?" do
    it "is false after revoke" do
      token, _ = ApiToken.create_with_token!(user: user, name: "test")
      token.revoke!
      expect(token.active?).to be_falsey
    end

    it "is false when expired" do
      token, _ = ApiToken.create_with_token!(user: user, name: "test", expires_at: 1.hour.ago)
      expect(token.active?).to be_falsey
    end
  end

  describe "#revoke! and devices" do
    it "deletes the device tokens registered with it, leaving others" do
      token, = ApiToken.create_with_token!(user: user, name: "a")
      other, = ApiToken.create_with_token!(user: user, name: "b")
      mine = DeviceToken.create!(user: user, token: "dev-a-#{SecureRandom.hex(4)}", platform: "ios", api_token: token)
      kept = DeviceToken.create!(user: user, token: "dev-b-#{SecureRandom.hex(4)}", platform: "ios", api_token: other)
      token.revoke!
      expect(DeviceToken.exists?(mine.id)).to be(false)
      expect(DeviceToken.exists?(kept.id)).to be(true)
    end

    it "removes the device's push tickets too" do
      token, = ApiToken.create_with_token!(user: user, name: "a")
      d = DeviceToken.create!(user: user, token: "dev-t-#{SecureRandom.hex(4)}", platform: "ios", api_token: token)
      PushTicket.create!(device_token: d, ticket_id: "tk-#{SecureRandom.hex(4)}")
      expect { token.revoke! }.not_to raise_error
      expect(PushTicket.where(device_token_id: d.id)).to be_empty
    end
  end

  describe "DeviceToken.deliverable" do
    it "excludes revoked/expired tokens' devices, keeps nil-token and active ones" do
      live, = ApiToken.create_with_token!(user: user, name: "live")
      expired, = ApiToken.create_with_token!(user: user, name: "exp", expires_at: 1.hour.ago)
      mk = ->(tok) { DeviceToken.create!(user: user, token: "d-#{SecureRandom.hex(6)}", platform: "ios", api_token: tok) }
      a, b, c = mk.(live), mk.(expired), mk.(nil)
      expect(DeviceToken.deliverable.pluck(:id)).to match_array([ a.id, c.id ])
      expect(DeviceToken.deliverable.pluck(:id)).not_to include(b.id)
    end
  end
end

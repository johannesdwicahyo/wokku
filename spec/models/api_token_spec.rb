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
end

require "rails_helper"

RSpec.describe DeviceToken do
  describe "validations" do
    it "is valid with token, platform, and user" do
      dt = DeviceToken.new(token: "unique-token-xyz", platform: "ios", user: users(:one))
      expect(dt).to be_valid
    end

    it "is invalid without token" do
      dt = DeviceToken.new(platform: "ios", user: users(:one))
      expect(dt).not_to be_valid
      expect(dt.errors[:token]).to include("can't be blank")
    end

    it "is invalid with duplicate token" do
      existing = device_tokens(:one)
      dt = DeviceToken.new(token: existing.token, platform: "android", user: users(:two))
      expect(dt).not_to be_valid
      expect(dt.errors[:token]).to include("has already been taken")
    end

    it "is invalid without platform" do
      dt = DeviceToken.new(token: "some-token-abc", user: users(:one))
      expect(dt).not_to be_valid
      expect(dt.errors[:platform]).to include("can't be blank")
    end

    it "is invalid with unsupported platform" do
      dt = DeviceToken.new(token: "some-token-abc", platform: "windows", user: users(:one))
      expect(dt).not_to be_valid
      expect(dt.errors[:platform]).to include("is not included in the list")
    end

    it "is valid for ios platform" do
      dt = DeviceToken.new(token: "ios-token-test", platform: "ios", user: users(:one))
      expect(dt).to be_valid
    end

    it "is valid for android platform" do
      dt = DeviceToken.new(token: "android-token-test", platform: "android", user: users(:two))
      expect(dt).to be_valid
    end

    it "is valid for macos platform" do
      dt = DeviceToken.new(token: "macos-token-test", platform: "macos", user: users(:two))
      expect(dt).to be_valid
    end
  end

  describe "associations" do
    it "belongs to user" do
      dt = device_tokens(:one)
      expect(dt.user).to eq(users(:one))
    end

    it "user has many device_tokens" do
      user = users(:one)
      expect(user.device_tokens).to include(device_tokens(:one))
    end

    it "destroying user destroys associated device_tokens" do
      user = User.create!(email: "token-owner@example.com", password: "password123456")
      DeviceToken.create!(token: "dependent-token-001", platform: "ios", user: user)
      expect { user.destroy }.to change { DeviceToken.count }.by(-1)
    end
  end
end

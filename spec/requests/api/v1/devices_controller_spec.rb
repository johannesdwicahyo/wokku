# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API::V1::DevicesController", type: :request do
  let(:user) { User.create!(email: "devices-test@example.com", password: "password123456") }
  let(:plain_token) { api_v1_token_for(user) }
  let(:headers) { { "Authorization" => "Bearer #{plain_token}" } }

  it "create returns 401 without token" do
    post api_v1_devices_path, params: { token: "device-token-abc", platform: "ios" }
    expect(response).to have_http_status(:unauthorized)
  end

  it "destroy returns 401 without token" do
    delete api_v1_device_path("device-token-abc")
    expect(response).to have_http_status(:unauthorized)
  end

  it "create registers a device token" do
    unique_token = "device-token-ios-#{SecureRandom.hex(8)}"
    post api_v1_devices_path,
      params: { token: unique_token, platform: "ios" },
      headers: headers
    expect(response).to have_http_status(:success)
    expect(JSON.parse(response.body)["registered"]).to eq(true)
  end

  it "create registers an android device token" do
    unique_token = "device-token-android-#{SecureRandom.hex(8)}"
    post api_v1_devices_path,
      params: { token: unique_token, platform: "android" },
      headers: headers
    expect(response).to have_http_status(:success)
    expect(JSON.parse(response.body)["registered"]).to eq(true)
  end

  it "create returns error for invalid platform" do
    unique_token = "device-token-bad-#{SecureRandom.hex(8)}"
    post api_v1_devices_path,
      params: { token: unique_token, platform: "windows" },
      headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "destroy unregisters a device token" do
    device = DeviceToken.create!(user: user, token: "device-to-delete", platform: "ios")
    delete api_v1_device_path(device.token), headers: headers
    expect(response).to have_http_status(:success)
    expect(JSON.parse(response.body)["unregistered"]).to eq(true)
    expect(DeviceToken.exists?(device.id)).to be_falsey
  end

  it "destroy returns success even if token not found" do
    delete api_v1_device_path("nonexistent-token"), headers: headers
    expect(response).to have_http_status(:success)
    expect(JSON.parse(response.body)["unregistered"]).to eq(true)
  end

  describe "a token already registered by another user" do
    let(:alice) { User.create!(email: "alice-dev@example.com", password: "password123456") }
    let(:bob) { User.create!(email: "bob-dev@example.com", password: "password123456") }
    let(:bob_headers) { { "Authorization" => "Bearer #{api_v1_token_for(bob)}" } }

    before { DeviceToken.create!(user: alice, token: "apns-shared", platform: "ios", provider: "apns") }

    it "moves the token to the account that registers it now" do
      post api_v1_devices_path, params: { token: "apns-shared", platform: "ios", provider: "apns" }, headers: bob_headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(DeviceToken.find_by(token: "apns-shared").user).to eq(bob)
      expect(alice.device_tokens).to be_empty
    end

    it "creates bob's default push row when it is bob's first device" do
      expect(Notification).to receive(:ensure_default_push_for!).with(bob)
      post api_v1_devices_path, params: { token: "apns-shared", platform: "ios", provider: "apns" }, headers: bob_headers, as: :json
    end
  end
end

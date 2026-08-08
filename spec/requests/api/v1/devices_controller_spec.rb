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
end

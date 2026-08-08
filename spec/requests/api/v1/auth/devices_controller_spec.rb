# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API::V1::Auth::DevicesController", type: :request do
  let(:user) { User.create!(email: "device-api@example.com", password: "password123456") }

  before { Rails.cache.clear }

  it "code returns device + user codes and verification URIs" do
    post api_v1_auth_device_code_path
    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["device_code"].length).to eq(64)
    expect(body["user_code"]).to match(/\A[A-Z]{4}-[A-Z]{4}\z/)
    expect(body["verification_uri"]).to include("/dashboard/device")
    expect(body["verification_uri_complete"]).to include(body["user_code"])
    expect(body["expires_in"]).to be > 0
    expect(body["interval"]).to be > 0
  end

  it "token returns authorization_pending while not approved" do
    auth = DeviceAuthorization.start!
    post api_v1_auth_device_token_path, params: { device_code: auth.device_code }
    expect(response).to have_http_status(:accepted)
    expect(JSON.parse(response.body)["error"]).to eq("authorization_pending")
  end

  it "token returns slow_down when polled too fast" do
    auth = DeviceAuthorization.start!
    auth.update!(last_polled_at: 1.second.ago)
    post api_v1_auth_device_token_path, params: { device_code: auth.device_code }
    expect(response).to have_http_status(:bad_request)
    expect(JSON.parse(response.body)["error"]).to eq("slow_down")
  end

  it "token returns expired_token for unknown code" do
    post api_v1_auth_device_token_path, params: { device_code: "nope" }
    expect(response).to have_http_status(:gone)
    expect(JSON.parse(response.body)["error"]).to eq("expired_token")
  end

  it "token returns expired_token for expired record" do
    auth = DeviceAuthorization.start!
    auth.update_column(:expires_at, 1.minute.ago)
    post api_v1_auth_device_token_path, params: { device_code: auth.device_code }
    expect(response).to have_http_status(:gone)
  end

  it "token returns access_denied when denied" do
    auth = DeviceAuthorization.start!
    auth.deny!
    post api_v1_auth_device_token_path, params: { device_code: auth.device_code }
    expect(response).to have_http_status(:forbidden)
    expect(JSON.parse(response.body)["error"]).to eq("access_denied")
  end

  it "token returns plain token after approval, exactly once" do
    auth = DeviceAuthorization.start!
    auth.approve!(user)
    post api_v1_auth_device_token_path, params: { device_code: auth.device_code }
    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["token"].length).to eq(64)
    expect(body["user"]["email"]).to eq(user.email)

    auth.update!(last_polled_at: 1.hour.ago)
    post api_v1_auth_device_token_path, params: { device_code: auth.device_code }
    expect(response).to have_http_status(:gone)
    expect(JSON.parse(response.body)["error"]).to eq("token_already_retrieved")
  end
end

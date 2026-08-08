# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API::V1::AuthController", type: :request do
  let(:user) { User.create!(email: "test@example.com", password: "password123456") }
  let(:token_and_plain) { ApiToken.create_with_token!(user: user, name: "test") }
  let(:token) { token_and_plain[0] }
  let(:plain_token) { token_and_plain[1] }
  let(:headers) { { "Authorization" => "Bearer #{plain_token}" } }

  it "login returns token" do
    post api_v1_auth_login_path, params: { email: user.email, password: "password123456" }
    expect(response).to have_http_status(:created)
    expect(JSON.parse(response.body)["token"]).not_to be_nil
  end

  it "login rejects bad password" do
    post api_v1_auth_login_path, params: { email: user.email, password: "wrong" }
    expect(response).to have_http_status(:unauthorized)
  end

  it "whoami returns current user" do
    get api_v1_auth_whoami_path, headers: headers
    expect(response).to have_http_status(:success)
    expect(JSON.parse(response.body)["email"]).to eq(user.email)
  end

  it "logout revokes token" do
    delete api_v1_auth_logout_path, headers: headers
    expect(response).to have_http_status(:success)
    expect(token.reload.revoked?).to be_truthy
  end

  it "returns 401 without token" do
    get api_v1_auth_whoami_path
    expect(response).to have_http_status(:unauthorized)
  end

  it "returns 401 with invalid token" do
    get api_v1_auth_whoami_path, headers: { "Authorization" => "Bearer invalid" }
    expect(response).to have_http_status(:unauthorized)
  end
end

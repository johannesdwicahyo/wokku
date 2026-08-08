# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API::V1::Auth::TokensController", type: :request do
  let(:user) { User.create!(email: "tokens-test@example.com", password: "password123456") }
  let(:token_and_plain) { ApiToken.create_with_token!(user: user, name: "test-token") }
  let(:token) { token_and_plain[0] }
  let(:plain_token) { token_and_plain[1] }
  let(:headers) { { "Authorization" => "Bearer #{plain_token}" } }

  it "index returns 401 without token" do
    get api_v1_auth_tokens_path
    expect(response).to have_http_status(:unauthorized)
  end

  it "create returns 401 without token" do
    post api_v1_auth_tokens_path, params: { name: "new-token" }
    expect(response).to have_http_status(:unauthorized)
  end

  it "destroy returns 401 without token" do
    delete api_v1_auth_token_path(token)
    expect(response).to have_http_status(:unauthorized)
  end

  it "index returns active tokens for current user" do
    get api_v1_auth_tokens_path, headers: headers
    expect(response).to have_http_status(:success)
    tokens = JSON.parse(response.body)
    expect(tokens).to be_a(Array)
    expect(tokens.length).to eq(1)
    expect(tokens.first["name"]).to eq("test-token")
  end

  it "create generates a new API token" do
    post api_v1_auth_tokens_path, params: { name: "my-new-token" }, headers: headers
    expect(response).to have_http_status(:created)
    body = JSON.parse(response.body)
    expect(body).to have_key("token")
    expect(body["name"]).to eq("my-new-token")
    expect(body["id"]).to be_present
  end

  it "create generates token with default name when name not provided" do
    post api_v1_auth_tokens_path, headers: headers
    expect(response).to have_http_status(:created)
    body = JSON.parse(response.body)
    expect(body).to have_key("token")
    expect(body["name"]).to be_present
  end

  it "destroy revokes a token" do
    ApiToken.create_with_token!(user: user, name: "to-revoke")
    other_token = user.api_tokens.find_by(name: "to-revoke")
    delete api_v1_auth_token_path(other_token), headers: headers
    expect(response).to have_http_status(:success)
    body = JSON.parse(response.body)
    expect(body["message"]).to eq("Token revoked")
    expect(other_token.reload.revoked?).to be_truthy
  end
end

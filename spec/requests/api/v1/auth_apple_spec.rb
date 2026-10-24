require "rails_helper"

RSpec.describe "POST /api/v1/auth/apple", type: :request do
  let(:env) do
    { "APPLE_TEAM_ID" => "TEAM123456", "APPLE_KEY_ID" => "KEY1234567", "APPLE_BUNDLE_ID" => "cloud.wokku.app",
      "APPLE_PRIVATE_KEY" => OpenSSL::PKey::EC.generate("prime256v1").to_pem.gsub("\n", "\\n") }
  end
  let(:claims) { { "sub" => "001.apple", "email" => "new@example.com", "email_verified" => true } }
  let(:body) { { identity_token: "t", nonce: "n" } }

  before do
    stub_const("ENV", ENV.to_h.merge(env))
    allow(Apple::IdentityToken).to receive(:verify!).with("t", nonce: "n").and_return(claims)
  end

  it "creates an account and returns an API token" do
    post "/api/v1/auth/apple", params: body, as: :json
    expect(response).to have_http_status(:created)
    json = response.parsed_body
    expect(json["token"]).to be_present
    expect(json["user"]["email"]).to eq("new@example.com")
    expect(User.find_by(apple_uid: "001.apple").teams).not_to be_empty
  end

  it "accepts a structured name on first sign-in" do
    post "/api/v1/auth/apple", params: body.merge(name: { given_name: "Jane", family_name: "Doe" }), as: :json
    expect(User.find_by(apple_uid: "001.apple").name).to eq("Jane Doe")
  end

  it "exchanges the authorization code and stores the refresh token" do
    expect(Apple::Client).to receive(:exchange_code).with("code1", client_id: "cloud.wokku.app").and_return("r1")
    post "/api/v1/auth/apple", params: body.merge(authorization_code: "code1"), as: :json
    user = User.find_by(apple_uid: "001.apple")
    expect([ user.apple_refresh_token, user.apple_token_client_id ]).to eq([ "r1", "cloud.wokku.app" ])
  end

  it "still signs in when the code exchange fails" do
    allow(Apple::Client).to receive(:exchange_code).and_return(nil)
    post "/api/v1/auth/apple", params: body.merge(authorization_code: "bad"), as: :json
    expect(response).to have_http_status(:created)
  end

  it "422s without identity_token or nonce" do
    post "/api/v1/auth/apple", params: { identity_token: "t" }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["error_code"]).to eq("invalid_params")
  end

  it "401s an invalid token without leaking the reason" do
    allow(Apple::IdentityToken).to receive(:verify!).and_raise(Apple::IdentityToken::Invalid, "JWT::ExpiredSignature")
    post "/api/v1/auth/apple", params: body, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body["error_code"]).to eq("invalid_token")
    expect(response.body).not_to include("ExpiredSignature")
  end

  it "503s retryable when Apple's keys are unreachable" do
    allow(Apple::IdentityToken).to receive(:verify!).and_raise(Apple::IdentityToken::Unavailable)
    post "/api/v1/auth/apple", params: body, as: :json
    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body).to include("error_code" => "apple_upstream_failed", "retryable" => true)
  end

  it "503s when Apple is not configured" do
    stub_const("ENV", ENV.to_h.except("APPLE_TEAM_ID"))
    post "/api/v1/auth/apple", params: body, as: :json
    expect(response.parsed_body["error_code"]).to eq("apple_unavailable")
  end

  it "403s an admin account" do
    admin = User.find_by(email: User::ADMIN_EMAIL) || create(:user, :admin, email: User::ADMIN_EMAIL)
    admin.update_columns(apple_uid: "001.apple")
    post "/api/v1/auth/apple", params: body, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body["error_code"]).to eq("not_authorized")
  end

  it "403s registration_closed when no account may be created" do
    allow(Wokku.config).to receive(:open_registration).and_return(false)
    post "/api/v1/auth/apple", params: body, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body["error_code"]).to eq("registration_closed")
  end
end

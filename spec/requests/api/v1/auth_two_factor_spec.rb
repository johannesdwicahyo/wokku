# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API auth with 2FA", type: :request do
  let(:user) do
    create(:user, email: "twofa@example.com", otp_secret: User.generate_otp_secret, otp_required_for_login: true)
  end
  let(:creds) { { email: user.email, password: "supersecret123" } }

  describe "POST /api/v1/auth/login" do
    it "401s a non-admin 2FA user without otp_code" do
      expect { post api_v1_auth_login_path, params: creds }.not_to change(ApiToken, :count)
      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to be_present
    end

    it "201s with a current TOTP" do
      post api_v1_auth_login_path, params: creds.merge(otp_code: user.current_otp)
      expect(response).to have_http_status(:created)
    end

    it "201s with a recovery code, once" do
      code = user.generate_otp_backup_codes!.first
      user.save!
      post api_v1_auth_login_path, params: creds.merge(otp_code: code)
      expect(response).to have_http_status(:created)
      post api_v1_auth_login_path, params: creds.merge(otp_code: code)
      expect(response).to have_http_status(:unauthorized)
    end

    it "still 403s an admin without 2FA" do
      admin = User.find_by(email: User::ADMIN_EMAIL) || create(:user, :admin, email: User::ADMIN_EMAIL)
      admin.update!(password: "supersecret123", otp_required_for_login: false)
      post api_v1_auth_login_path, params: { email: admin.email, password: "supersecret123" }
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /api/v1/auth/apple" do
    let(:env) do
      { "APPLE_TEAM_ID" => "TEAM123456", "APPLE_KEY_ID" => "KEY1234567", "APPLE_BUNDLE_ID" => "cloud.wokku.app",
        "APPLE_PRIVATE_KEY" => OpenSSL::PKey::EC.generate("prime256v1").to_pem.gsub("\n", "\\n") }
    end

    before do
      stub_const("ENV", ENV.to_h.merge(env))
      user.update_columns(apple_uid: "001.apple2fa")
      allow(Apple::IdentityToken).to receive(:verify!).with("t", nonce: "n")
        .and_return({ "sub" => "001.apple2fa", "email" => user.email, "email_verified" => true })
    end

    it "refuses a 2FA user with two_factor_required and issues no token" do
      expect {
        post "/api/v1/auth/apple", params: { identity_token: "t", nonce: "n" }, as: :json
      }.not_to change(ApiToken, :count)
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["error_code"]).to eq("two_factor_required")
      expect(response.parsed_body["error"]).to include("browser")
    end
  end
end

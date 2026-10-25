# frozen_string_literal: true

require "openapi_helper"

RSpec.describe "API v1 auth", type: :request do
  let(:user) { User.create!(email: "auth-openapi@example.com", password: "password123456") }
  let(:Authorization) { "Bearer #{api_v1_token_for(user)}" }

  # AuthController renders its own ad-hoc { error: "..." } bodies (not ApiErrors).
  login_error = { type: :object, required: %w[error], properties: { error: { type: :string } } }

  path "/api/v1/auth/login" do
    post "Exchange email + password (+ otp_code for admins) for an API token" do
      operationId "auth.login"
      tags "auth"
      security []
      consumes "application/json"
      produces "application/json"
      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: %w[email password],
        properties: {
          email: { type: :string },
          password: { type: :string },
          otp_code: { type: :string, description: "Required for admin users" },
          name: { type: :string, description: "Label for the new token" }
        }
      }

      response "201", "token created" do
        let(:payload) { { email: user.email, password: "password123456" } }
        schema type: :object,
               required: %w[token user],
               properties: {
                 token: { type: :string },
                 user: {
                   type: :object,
                   required: %w[id email role],
                   properties: { id: { type: :string, format: :uuid }, email: { type: :string }, role: { type: :string } }
                 }
               }
        run_test!
      end

      response "401", "invalid credentials (or bad/missing admin OTP)" do
        let(:payload) { { email: user.email, password: "wrong" } }
        schema login_error
        run_test!
      end
    end
  end

  path "/api/v1/auth/apple" do
    post "Exchange an Apple identity token (iOS Sign in with Apple) for an API token" do
      operationId "auth.apple"
      tags "auth"
      security []
      consumes "application/json"
      produces "application/json"
      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: %w[identity_token nonce],
        properties: {
          identity_token: { type: :string, description: "Apple identity token (JWT)" },
          nonce: { type: :string, description: "Raw nonce whose SHA-256 was sent in the Apple request" },
          authorization_code: { type: :string, description: "One-time code; stored as a refresh token for revocation" },
          name: { type: :object, properties: { given_name: { type: :string }, family_name: { type: :string } } },
          token_name: { type: :string, description: "Label for the new API token" }
        }
      }

      let(:apple_env) do
        { "APPLE_TEAM_ID" => "TEAM123456", "APPLE_KEY_ID" => "KEY1234567", "APPLE_BUNDLE_ID" => "cloud.wokku.app",
          "APPLE_PRIVATE_KEY" => OpenSSL::PKey::EC.generate("prime256v1").to_pem.gsub("\n", "\\n") }
      end
      let(:payload) { { identity_token: "t", nonce: "n" } }
      before do
        stub_const("ENV", ENV.to_h.merge(apple_env))
        allow(Apple::IdentityToken).to receive(:verify!)
          .and_return({ "sub" => "001.rswag", "email" => "apple-openapi@example.com", "email_verified" => true })
      end

      response "201", "token created" do
        schema type: :object,
               required: %w[token user],
               properties: {
                 token: { type: :string },
                 user: {
                   type: :object,
                   required: %w[id email role],
                   properties: { id: { type: :string, format: :uuid }, email: { type: :string }, role: { type: :string } }
                 }
               }
        run_test!
      end

      response "401", "identity token invalid, expired, wrong audience or nonce (invalid_token)" do
        before { allow(Apple::IdentityToken).to receive(:verify!).and_raise(Apple::IdentityToken::Invalid) }
        schema "$ref" => "#/components/schemas/Error"
        run_test!
      end

      response "403", "admin account, or no account may be created (not_authorized | registration_closed)" do
        before { allow(Wokku.config).to receive(:open_registration).and_return(false) }
        schema "$ref" => "#/components/schemas/Error"
        run_test!
      end

      response "422", "identity_token or nonce missing (invalid_params)" do
        let(:payload) { { identity_token: "t" } }
        schema "$ref" => "#/components/schemas/Error"
        run_test!
      end

      response "503", "Apple not configured (apple_unavailable) or unreachable (apple_upstream_failed)" do
        before { allow(Apple::IdentityToken).to receive(:verify!).and_raise(Apple::IdentityToken::Unavailable) }
        schema "$ref" => "#/components/schemas/Error"
        run_test!
      end
    end
  end

  path "/api/v1/auth/mobile/token" do
    post "Redeem an iOS web sign-in handoff code (PKCE) for an API token" do
      operationId "auth.mobile_token"
      tags "auth"
      security []
      consumes "application/json"
      produces "application/json"
      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: %w[code code_verifier],
        properties: {
          code: { type: :string, description: "One-time code from wokku://auth" },
          code_verifier: { type: :string, description: "PKCE verifier (43-128 chars) whose S256 hash started the flow" },
          token_name: { type: :string, description: "Label for the new API token" }
        }
      }

      let(:mobile_user) { User.create!(email: "mobile-openapi@example.com", password: "password123456") }
      let(:verifier) { "v" * 64 }
      let(:mobile_code) do
        MobileAuthCode.issue!(user: mobile_user, code_challenge: Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false))
      end
      let(:payload) { { code: mobile_code, code_verifier: verifier } }

      response "201", "token created" do
        schema type: :object,
               required: %w[token user],
               properties: {
                 token: { type: :string },
                 user: {
                   type: :object,
                   required: %w[id email role],
                   properties: { id: { type: :string, format: :uuid }, email: { type: :string }, role: { type: :string } }
                 }
               }
        run_test!
      end

      response "401", "code unknown, used, expired, or verifier mismatch (invalid_token)" do
        let(:payload) { { code: "unknown", code_verifier: verifier } }
        schema "$ref" => "#/components/schemas/Error"
        run_test!
      end

      response "422", "code missing or verifier not 43-128 chars (invalid_params)" do
        let(:payload) { { code: "x" } }
        schema "$ref" => "#/components/schemas/Error"
        run_test!
      end
    end
  end

  path "/api/v1/auth/logout" do
    delete "Revoke the calling token" do
      operationId "auth.logout"
      tags "auth"
      security [ { bearer: [] } ]
      produces "application/json"

      response "200", "token revoked" do
        schema type: :object, required: %w[message], properties: { message: { type: :string } }
        run_test!
      end

      response "401", "missing or invalid token" do
        let(:Authorization) { nil }
        schema "$ref" => "#/components/schemas/Error"
        run_test!
      end
    end
  end

  path "/api/v1/auth/whoami" do
    get "Current user" do
      operationId "auth.whoami"
      tags "auth"
      security [ { bearer: [] } ]
      produces "application/json"

      response "200", "current user" do
        schema type: :object,
               required: %w[id email role],
               properties: { id: { type: :string, format: :uuid }, email: { type: :string }, role: { type: :string } }
        run_test!
      end

      response "401", "missing or invalid token" do
        let(:Authorization) { nil }
        schema "$ref" => "#/components/schemas/Error"
        run_test!
      end
    end
  end
end

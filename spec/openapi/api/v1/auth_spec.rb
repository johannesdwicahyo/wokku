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

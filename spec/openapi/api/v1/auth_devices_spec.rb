# frozen_string_literal: true

require "openapi_helper"

RSpec.describe "API v1 auth device flow", type: :request do
  # Device-flow polling answers with OAuth-style { error: "<reason>" } bodies.
  oauth_error = { type: :object, required: %w[error], properties: { error: { type: :string } } }

  path "/api/v1/auth/device/code" do
    post "Start the device authorization flow" do
      operationId "auth_devices.code"
      tags "auth"
      security []
      produces "application/json"

      response "200", "device + user codes" do
        schema type: :object,
               required: %w[device_code user_code verification_uri verification_uri_complete expires_in interval],
               properties: {
                 device_code: { type: :string },
                 user_code: { type: :string },
                 verification_uri: { type: :string },
                 verification_uri_complete: { type: :string },
                 expires_in: { type: :integer },
                 interval: { type: :integer }
               }
        run_test!
      end
    end
  end

  path "/api/v1/auth/device/token" do
    post "Poll for the token once the user approved the device" do
      operationId "auth_devices.token"
      tags "auth"
      security []
      consumes "application/json"
      produces "application/json"
      parameter name: :payload, in: :body, schema: {
        type: :object, required: %w[device_code], properties: { device_code: { type: :string } }
      }

      let(:auth) { DeviceAuthorization.start! }
      let(:payload) { { device_code: auth.device_code } }

      response "200", "approved; token returned once" do
        let(:approver) { User.create!(email: "device-approver@example.com", password: "password123456") }
        before { auth.approve!(approver) }
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

      response "202", "authorization_pending" do
        schema oauth_error
        run_test!
      end

      response "400", "slow_down (polled faster than interval)" do
        before { auth.touch_polled! }
        schema oauth_error
        run_test!
      end

      response "403", "access_denied" do
        before { auth.deny! }
        schema oauth_error
        run_test!
      end

      response "410", "expired_token (unknown or expired code) or token_already_retrieved" do
        let(:payload) { { device_code: "nope" } }
        schema oauth_error
        run_test!
      end
    end
  end
end

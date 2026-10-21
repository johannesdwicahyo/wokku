# frozen_string_literal: true

require "openapi_helper"

RSpec.describe "API v1 devices", type: :request do
  let(:user) { users(:one) }
  let(:Authorization) { "Bearer #{api_v1_token_for(user)}" }

  path "/api/v1/devices" do
    post "Register a push device token" do
      operationId "devices.create"
      tags "devices"
      security [ { bearer: [] } ]
      consumes "application/json"
      produces "application/json"
      parameter name: :payload, in: :body, schema: { "$ref" => "#/components/schemas/Device" }

      response "200", "registered" do
        let(:payload) { { token: "tok-#{SecureRandom.hex(6)}", platform: "ios" } }
        schema type: :object, required: %w[registered], properties: { registered: { type: :boolean } }
        run_test!
      end

      response "401", "missing or invalid token" do
        let(:Authorization) { nil }
        let(:payload) { { token: "x", platform: "ios" } }
        schema "$ref" => "#/components/schemas/Error"
        run_test!
      end

      response "422", "invalid platform" do
        let(:payload) { { token: "tok-#{SecureRandom.hex(6)}", platform: "windows" } }
        schema "$ref" => "#/components/schemas/Error"
        run_test!
      end
    end
  end

  path "/api/v1/devices/{id}" do
    # The id is the device token string itself.
    parameter name: :id, in: :path, schema: { type: :string }

    delete "Unregister a push device token (idempotent; always 200)" do
      operationId "devices.delete"
      tags "devices"
      security [ { bearer: [] } ]
      produces "application/json"

      response "200", "unregistered" do
        let(:id) { DeviceToken.create!(user: user, token: "to-delete", platform: "ios").token }
        schema type: :object, required: %w[unregistered], properties: { unregistered: { type: :boolean } }
        run_test!
      end
    end
  end
end

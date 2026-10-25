# frozen_string_literal: true

require "openapi_helper"

RSpec.describe "API v1 account deletion", type: :request do
  let(:user) { User.create!(email: "delete-openapi@example.com", password: "password123456") }
  let(:Authorization) { "Bearer #{api_v1_token_for(user)}" }

  path "/api/v1/account/deletion" do
    post "Schedule deletion of the caller's account (3-day grace; signs out every client)" do
      operationId "account_deletion.create"
      tags "account"
      security [ { bearer: [] } ]
      consumes "application/json"
      produces "application/json"
      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: %w[confirm_email],
        properties: { confirm_email: { type: :string, description: "Must equal the account email" } }
      }

      response "202", "deletion scheduled" do
        let(:payload) { { confirm_email: user.email } }
        schema type: :object, required: %w[purge_at], properties: { purge_at: { type: :string, format: "date-time" } }
        run_test!
      end

      response "409", "deletion already scheduled (already_exists)" do
        before { user.schedule_deletion! }
        let(:payload) { { confirm_email: user.email } }
        schema "$ref" => "#/components/schemas/Error"
        run_test!
      end

      response "422", "confirm_email does not match (invalid_params)" do
        let(:payload) { { confirm_email: "someone-else@example.com" } }
        schema "$ref" => "#/components/schemas/Error"
        run_test!
      end
    end
  end
end

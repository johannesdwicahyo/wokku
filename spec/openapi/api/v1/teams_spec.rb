# frozen_string_literal: true

require "openapi_helper"

RSpec.describe "API v1 teams", type: :request do
  let(:user) { users(:one) }
  let(:Authorization) { "Bearer #{api_v1_token_for(user)}" }

  path "/api/v1/teams" do
    get "List the caller's teams" do
      operationId "teams.list"
      tags "teams"
      security [ { bearer: [] } ]
      produces "application/json"

      response "200", "teams" do
        schema type: :array, items: { "$ref" => "#/components/schemas/Team" }
        run_test!
      end

      response "401", "missing or invalid token" do
        let(:Authorization) { nil }
        schema "$ref" => "#/components/schemas/Error"
        run_test!
      end
    end

    post "Create a team (caller becomes admin)" do
      operationId "teams.create"
      tags "teams"
      security [ { bearer: [] } ]
      consumes "application/json"
      produces "application/json"
      parameter name: :payload, in: :body, schema: {
        type: :object, required: %w[name], properties: { name: { type: :string } }
      }

      response "201", "team created" do
        let(:payload) { { name: "openapi-team-#{SecureRandom.hex(3)}" } }
        schema "$ref" => "#/components/schemas/Team"
        run_test!
      end

      response "422", "invalid (blank or taken name)" do
        let(:payload) { { name: "" } }
        schema "$ref" => "#/components/schemas/Error"
        run_test!
      end
    end
  end
end

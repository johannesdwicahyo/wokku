# frozen_string_literal: true

require "openapi_helper"

RSpec.describe "API v1 activities", type: :request do
  let(:user) { users(:one) }
  let(:Authorization) { "Bearer #{api_v1_token_for(user)}" }

  path "/api/v1/activities" do
    get "Recent activity for the caller's first team" do
      operationId "activities.list"
      tags "activities"
      security [ { bearer: [] } ]
      produces "application/json"
      parameter name: :limit, in: :query, required: false, schema: { type: :integer, minimum: 1, maximum: 200, default: 50 }

      response "200", "activities, newest first" do
        before { Activity.create!(user: user, team: user.teams.first, action: "app.created", target_type: "AppRecord", target_name: "demo") }
        schema type: :array, items: { "$ref" => "#/components/schemas/Activity" }
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

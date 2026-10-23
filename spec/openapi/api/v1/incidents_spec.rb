# frozen_string_literal: true

require "openapi_helper"

RSpec.describe "API v1 incidents", type: :request do
  let(:user) { users(:one) }
  let(:Authorization) { "Bearer #{api_v1_token_for(user)}" }
  incident_schema = {
    type: :object,
    required: %w[id subject_type reason started_at open],
    properties: {
      id: { type: :string, format: :uuid },
      subject_type: { type: :string, enum: %w[app server] },
      app_id: { type: :string, format: :uuid, nullable: true },
      app_name: { type: :string, nullable: true },
      server_id: { type: :string, format: :uuid, nullable: true },
      reason: { type: :string },
      started_at: { type: :string, format: "date-time" },
      resolved_at: { type: :string, format: "date-time", nullable: true },
      duration_seconds: { type: :integer, nullable: true, description: "null while open" },
      open: { type: :boolean }
    }
  }

  path "/api/v1/incidents" do
    get "List outages of apps the caller can see (host outages: system admin only)" do
      operationId "incidents.list"
      tags "incidents"
      security [ { bearer: [] } ]
      produces "application/json"
      parameter name: :state, in: :query, required: false, schema: { type: :string, enum: %w[open all], default: "open" }
      parameter name: :app_id, in: :query, required: false, schema: { type: :string }, description: "App UUID or name"
      parameter name: :before, in: :query, required: false, schema: { type: :string, format: "date-time" }, description: "Cursor: only incidents that started before this time"
      parameter name: :limit, in: :query, required: false, schema: { type: :integer, minimum: 1, maximum: 200, default: 50 }

      response "200", "incidents, newest started_at first" do
        before { create(:incident, app_record: app_records(:one)) }
        schema type: :array, items: incident_schema
        run_test!
      end

      response "401", "missing or invalid token" do
        let(:Authorization) { nil }
        schema "$ref" => "#/components/schemas/Error"
        run_test!
      end

      response "422", "invalid state, limit or before" do
        let(:limit) { 500 }
        schema "$ref" => "#/components/schemas/Error"
        run_test!
      end
    end
  end

  path "/api/v1/incidents/{id}" do
    parameter name: :id, in: :path, schema: { type: :string, format: :uuid }

    get "Show one incident" do
      operationId "incidents.show"
      tags "incidents"
      security [ { bearer: [] } ]
      produces "application/json"

      response "200", "incident" do
        let(:id) { create(:incident, app_record: app_records(:one)).id }
        schema incident_schema
        run_test!
      end

      response "404", "unknown, or not visible to the caller" do
        let(:id) { create(:incident, :for_server).id }
        schema "$ref" => "#/components/schemas/Error"
        run_test!
      end
    end
  end
end

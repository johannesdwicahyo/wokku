# frozen_string_literal: true

require "openapi_helper"

RSpec.describe "API v1 notifications", type: :request do
  let(:user) { users(:one) }
  let(:team) { teams(:one) }
  let(:Authorization) { "Bearer #{api_v1_token_for(user)}" }
  notification_schema = {
    type: :object,
    required: %w[id team_id channel events],
    properties: {
      id: { type: :string, format: :uuid },
      team_id: { type: :string, format: :uuid },
      app_record_id: { type: :string, format: :uuid, nullable: true },
      channel: { type: :string, enum: %w[email slack webhook discord telegram push] },
      events: { type: :array, items: { type: :string } },
      config: { type: :object, nullable: true },
      created_at: { type: :string, format: "date-time" },
      updated_at: { type: :string, format: "date-time" }
    }
  }

  path "/api/v1/notifications" do
    get "List notification rules for the caller's teams" do
      operationId "notifications.list"
      tags "notifications"
      security [ { bearer: [] } ]
      produces "application/json"

      response "200", "notifications" do
        schema type: :array, items: notification_schema
        run_test!
      end

      response "401", "missing or invalid token" do
        let(:Authorization) { nil }
        schema "$ref" => "#/components/schemas/Error"
        run_test!
      end
    end

    post "Create a notification rule (team admin only)" do
      operationId "notifications.create"
      tags "notifications"
      security [ { bearer: [] } ]
      consumes "application/json"
      produces "application/json"
      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: %w[team_id channel events],
        properties: {
          team_id: { type: :string, format: :uuid },
          channel: { type: :string, enum: %w[email slack webhook discord telegram push] },
          events: { type: :array, items: { type: :string } },
          app_record_id: { type: :string, format: :uuid },
          config: { type: :object }
        }
      }

      response "201", "created" do
        let(:payload) { { team_id: team.id, channel: "email", events: [ "deploy_succeeded" ] } }
        schema notification_schema
        run_test!
      end

      response "422", "invalid (no events)" do
        let(:payload) { { team_id: team.id, channel: "email", events: [] } }
        schema "$ref" => "#/components/schemas/Error"
        run_test!
      end
    end
  end

  path "/api/v1/notifications/{id}" do
    parameter name: :id, in: :path, schema: { type: :string, format: :uuid }

    delete "Delete a notification rule (team admin only)" do
      operationId "notifications.delete"
      tags "notifications"
      security [ { bearer: [] } ]
      produces "application/json"

      response "200", "deleted" do
        let(:id) { Notification.create!(team: team, channel: :email, events: [ "deploy_succeeded" ]).id }
        schema type: :object, required: %w[message], properties: { message: { type: :string } }
        run_test!
      end

      response "404", "notification of a team the caller does not belong to" do
        let(:id) do
          owner = User.create!(email: "notif-owner@example.com", password: "password123456")
          other = Team.create!(name: "notif-foreign", owner: owner)
          Notification.create!(team: other, channel: :email, events: [ "deploy_succeeded" ]).id
        end
        schema "$ref" => "#/components/schemas/Error"
        run_test!
      end
    end
  end
end

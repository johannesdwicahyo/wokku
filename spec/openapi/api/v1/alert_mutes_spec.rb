# frozen_string_literal: true

require "openapi_helper"

RSpec.describe "API v1 alert mutes", type: :request do
  let(:user) { users(:one) }
  let(:app_record) { app_records(:one) }
  let(:Authorization) { "Bearer #{api_v1_token_for(user)}" }
  mute_schema = {
    type: :object,
    required: %w[id created_at],
    properties: {
      id: { type: :string, format: :uuid },
      app_id: { type: :string, format: :uuid, nullable: true, description: "null = every app" },
      app_name: { type: :string, nullable: true },
      event: { type: :string, nullable: true, description: "null = every push event" },
      until: { type: :string, format: "date-time", nullable: true, description: "null = until removed" },
      created_at: { type: :string, format: "date-time" }
    }
  }

  path "/api/v1/alert_mutes" do
    get "List the caller's active push mutes" do
      operationId "alert_mutes.list"
      tags "alert_mutes"
      security [ { bearer: [] } ]
      produces "application/json"

      response "200", "active mutes (expired ones are omitted)" do
        before do
          AlertMute.create!(user: user, app_record: app_record, event: nil)
          AlertMute.create!(user: user, event: "deploy_failed", expires_at: 1.minute.ago)
        end
        schema type: :array, items: mute_schema
        run_test! do |response|
          expect(response.parsed_body.size).to eq(1)
        end
      end

      response "401", "missing or invalid token" do
        let(:Authorization) { nil }
        schema "$ref" => "#/components/schemas/Error"
        run_test!
      end
    end

    post "Mute push alerts for an app and/or an event (posting the same scope again updates its expiry)" do
      operationId "alert_mutes.create"
      tags "alert_mutes"
      security [ { bearer: [] } ]
      consumes "application/json"
      produces "application/json"
      parameter name: :payload, in: :body, schema: {
        type: :object,
        properties: {
          app_id: { type: :string, description: "App UUID or name" },
          event: { type: :string, enum: PushNotificationService::TITLES.keys },
          until: { type: :string, format: "date-time" }
        }
      }

      response "201", "muted" do
        let(:payload) { { app_id: app_record.name, event: "app_down", until: 1.hour.from_now.iso8601 } }
        schema mute_schema
        run_test!
      end

      response "201", "same scope again: expiry updated, no duplicate" do
        before { AlertMute.create!(user: user, app_record: app_record, event: "app_down") }
        let(:payload) { { app_id: app_record.id, event: "app_down", until: 2.hours.from_now.iso8601 } }
        schema mute_schema
        run_test! do
          expect(AlertMute.where(user: user).count).to eq(1)
          expect(AlertMute.last.expires_at).to be > 1.hour.from_now
        end
      end

      response "404", "app the caller cannot see" do
        let(:payload) { { app_id: create(:app_record).id } }
        schema "$ref" => "#/components/schemas/Error"
        run_test!
      end

      response "422", "neither app_id nor event (mute everything), unknown event, or bad until" do
        let(:payload) { {} }
        schema "$ref" => "#/components/schemas/Error"
        run_test! do |response|
          expect(response.parsed_body["error"]).to include("unregister the device")
        end
      end
    end
  end

  path "/api/v1/alert_mutes/{id}" do
    parameter name: :id, in: :path, schema: { type: :string, format: :uuid }

    delete "Remove one of the caller's mutes" do
      operationId "alert_mutes.destroy"
      tags "alert_mutes"
      security [ { bearer: [] } ]
      produces "application/json"

      response "200", "removed" do
        let(:id) { AlertMute.create!(user: user, event: "app_down").id }
        schema type: :object, required: %w[message], properties: { message: { type: :string } }
        run_test!
      end

      response "404", "another user's mute" do
        let(:id) { AlertMute.create!(user: create(:user), event: "app_down").id }
        schema "$ref" => "#/components/schemas/Error"
        run_test!
      end
    end
  end
end

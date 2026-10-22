# frozen_string_literal: true

require "openapi_helper"

# Env vars. GET returns VALUES to member+ (used by `config:export`); viewers get keys with null values and masked: true.
RSpec.describe "API v1 config", type: :request do
  let(:user) { users(:one) }
  let(:Authorization) { "Bearer #{api_v1_token_for(user)}" }
  let(:app_record) { app_records(:one) }
  let(:foreign_app) { app_records(:two) }
  let(:viewer) { create(:user).tap { |u| create(:team_membership, user: u, team: app_record.team, role: :viewer) } }
  error = { "$ref" => "#/components/schemas/Error" }
  app_param = { name: :app_id, in: :path, schema: { type: :string }, description: "App UUID or name" }
  restart_note = { type: :object, required: %w[message restart_required], properties: {
    message: { type: :string }, restart_required: { type: :boolean },
    vars: { type: :array, items: { type: :string }, description: "Names set (PATCH/PUT)" },
    keys: { type: :array, items: { type: :string }, description: "Names removed (DELETE)" }
  } }

  path "/api/v1/apps/{app_id}/config" do
    parameter app_param

    get "Show the app's environment variables (values hidden from viewers)" do
      operationId "config.show"
      tags "config"
      security [ { bearer: [] } ]
      produces "application/json"

      response "200", "env var name => value" do
        let(:app_id) { app_record.id }
        schema type: :object, required: %w[config masked],
               properties: {
                 config: { type: :object, additionalProperties: { type: :string, nullable: true }, example: { "DATABASE_URL" => "postgres://user:pass@host/db" } },
                 masked: { type: :boolean, description: "true for viewers: values are null" }
               }
        run_test!
      end

      response "401", "missing or invalid token" do
        let(:app_id) { app_record.id }
        let(:Authorization) { nil }
        schema error
        run_test!
      end

      response "404", "unknown app, or an app of a team the caller does not belong to" do
        let(:app_id) { foreign_app.id }
        schema error
        run_test!
      end
    end

    [ [ :patch, "config.update", "Set environment variables (merge)" ],
      [ :put, "config.replace", "Set environment variables (same as PATCH)" ] ].each do |verb, op_id, summary|
      send(verb, summary) do
        operationId op_id
        tags "config"
        security [ { bearer: [] } ]
        consumes "application/json"
        produces "application/json"
        parameter name: :payload, in: :body, schema: {
          type: :object, required: %w[vars],
          properties: { vars: { type: :object, additionalProperties: { type: :string }, example: { "LOG_LEVEL" => "info" } } }
        }
        let(:app_id) { app_record.id }
        let(:payload) { { vars: { "LOG_LEVEL" => "info" } } }

        response "200", "vars written; restart the app to apply" do
          schema restart_note
          run_test!
        end

        response "400", "vars missing or empty (invalid_params)" do
          let(:payload) { { vars: {} } }
          schema error
          run_test!
        end

        response "401", "missing or invalid token" do
          let(:Authorization) { nil }
          schema error
          run_test!
        end

        response "403", "caller is a viewer on the app's team" do
          let(:Authorization) { "Bearer #{api_v1_token_for(viewer)}" }
          schema error
          run_test!
        end

        response "404", "unknown app, or an app of a team the caller does not belong to" do
          let(:app_id) { foreign_app.id }
          schema error
          run_test!
        end
      end
    end

    delete "Unset environment variables" do
      operationId "config.destroy"
      tags "config"
      security [ { bearer: [] } ]
      consumes "application/json"
      produces "application/json"
      parameter name: :payload, in: :body, schema: {
        type: :object, required: %w[keys], properties: { keys: { type: :array, items: { type: :string } } }
      }
      let(:app_id) { app_record.id }
      let(:payload) { { keys: [ "OLD_VAR" ] } }

      response "200", "vars removed; restart the app to apply" do
        schema restart_note
        run_test!
      end

      response "400", "keys missing or empty (invalid_params)" do
        let(:payload) { { keys: [] } }
        schema error
        run_test!
      end

      response "401", "missing or invalid token" do
        let(:Authorization) { nil }
        schema error
        run_test!
      end

      response "403", "caller is a viewer on the app's team" do
        let(:Authorization) { "Bearer #{api_v1_token_for(viewer)}" }
        schema error
        run_test!
      end

      response "404", "unknown app, or an app of a team the caller does not belong to" do
        let(:app_id) { foreign_app.id }
        schema error
        run_test!
      end
    end
  end
end

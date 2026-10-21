# frozen_string_literal: true

require "openapi_helper"

RSpec.describe "API v1 domains", type: :request do
  let(:user) { users(:one) }
  let(:Authorization) { "Bearer #{api_v1_token_for(user)}" }
  let(:app_record) { app_records(:one) }
  let(:foreign_app) { app_records(:two) }
  let(:domain) { domains(:one) }
  let(:viewer) { create(:user).tap { |u| create(:team_membership, user: u, team: app_record.team, role: :viewer) } }
  let(:viewer_auth) { "Bearer #{api_v1_token_for(viewer)}" }
  error = { "$ref" => "#/components/schemas/Error" }
  domain_schema = { "$ref" => "#/components/schemas/Domain" }
  app_param = { name: :app_id, in: :path, schema: { type: :string }, description: "App UUID or name" }
  message_schema = { type: :object, required: %w[message], properties: { message: { type: :string }, domain: { type: :string } } }

  path "/api/v1/apps/{app_id}/domains" do
    parameter app_param

    get "List the app's domains" do
      operationId "domains.list"
      tags "domains"
      security [ { bearer: [] } ]
      produces "application/json"

      response "200", "domains" do
        let(:app_id) { app_record.id }
        schema type: :array, items: domain_schema
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

    post "Add a custom domain" do
      operationId "domains.create"
      tags "domains"
      security [ { bearer: [] } ]
      consumes "application/json"
      produces "application/json"
      parameter name: :payload, in: :body, schema: {
        type: :object, required: %w[hostname], properties: { hostname: { type: :string, example: "www.example.com" } }
      }
      let(:app_id) { app_record.id }
      let(:payload) { { hostname: "new.example.com" } }

      response "201", "domain added" do
        schema domain_schema
        run_test!
      end

      response "401", "missing or invalid token" do
        let(:Authorization) { nil }
        schema error
        run_test!
      end

      response "403", "caller is a viewer on the app's team" do
        let(:Authorization) { viewer_auth }
        schema error
        run_test!
      end

      response "404", "unknown app, or an app of a team the caller does not belong to" do
        let(:app_id) { foreign_app.id }
        schema error
        run_test!
      end

      response "422", "blank or already-taken hostname (validation_failed)" do
        let(:payload) { { hostname: domain.hostname } }
        schema error
        run_test!
      end
    end
  end

  path "/api/v1/apps/{app_id}/domains/{id}" do
    parameter app_param
    parameter name: :id, in: :path, schema: { type: :string, format: :uuid }

    delete "Remove a domain" do
      operationId "domains.destroy"
      tags "domains"
      security [ { bearer: [] } ]
      produces "application/json"
      let(:app_id) { app_record.id }
      let(:id) { domain.id }

      response "200", "domain removed" do
        schema message_schema
        run_test!
      end

      response "401", "missing or invalid token" do
        let(:Authorization) { nil }
        schema error
        run_test!
      end

      response "403", "caller is a viewer on the app's team" do
        let(:Authorization) { viewer_auth }
        schema error
        run_test!
      end

      response "404", "unknown domain, or an app of a team the caller does not belong to" do
        let(:app_id) { foreign_app.id }
        schema error
        run_test!
      end
    end
  end

  path "/api/v1/apps/{app_id}/domains/{id}/ssl" do
    parameter app_param
    parameter name: :id, in: :path, schema: { type: :string, format: :uuid }

    post "Queue SSL certificate issuance for a domain" do
      operationId "domains.ssl"
      tags "domains"
      security [ { bearer: [] } ]
      produces "application/json"
      let(:app_id) { app_record.id }
      let(:id) { domain.id }

      response "202", "issuance queued" do
        schema message_schema
        run_test!
      end

      response "401", "missing or invalid token" do
        let(:Authorization) { nil }
        schema error
        run_test!
      end

      response "403", "caller is a viewer on the app's team" do
        let(:Authorization) { viewer_auth }
        schema error
        run_test!
      end

      response "404", "unknown domain, or an app of a team the caller does not belong to" do
        let(:app_id) { foreign_app.id }
        schema error
        run_test!
      end
    end
  end
end

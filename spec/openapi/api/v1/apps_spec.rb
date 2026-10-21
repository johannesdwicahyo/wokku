# frozen_string_literal: true

require "openapi_helper"

RSpec.describe "API v1 apps", type: :request do
  let(:user) { users(:one) }
  let(:Authorization) { "Bearer #{api_v1_token_for(user)}" }
  let(:app_record) { app_records(:one) }
  let(:foreign_app) { app_records(:two) }
  error = { "$ref" => "#/components/schemas/Error" }
  app_ref = { "$ref" => "#/components/schemas/App" }
  app_detail = { allOf: [ app_ref, { type: :object, required: %w[git_remote push_instructions] } ] }
  id_param = { name: :id, in: :path, schema: { type: :string }, description: "App UUID or name" }

  before do
    allow_any_instance_of(Apps::Lifecycle::DeployLock).to receive(:locked?).and_return(false)
    allow(Wokku.config.dns_provider).to receive(:create_app_record)
  end

  path "/api/v1/apps" do
    get "List the apps visible to the caller" do
      operationId "apps.list"
      tags "apps"
      security [ { bearer: [] } ]
      produces "application/json"
      parameter name: :q, in: :query, required: false, schema: { type: :string }, description: "Name substring filter"
      parameter name: :include_previews, in: :query, required: false, schema: { type: :string }, description: "Any value includes PR preview apps"

      response "200", "apps" do
        schema type: :array, items: app_ref
        run_test! { |response| expect(JSON.parse(response.body).map { |a| a["id"] }).to include(app_record.id) }
      end

      response "401", "missing or invalid token" do
        let(:Authorization) { nil }
        schema error
        run_test!
      end
    end

    post "Create an app" do
      operationId "apps.create"
      tags "apps"
      security [ { bearer: [] } ]
      consumes "application/json"
      produces "application/json"
      parameter name: :payload, in: :body, schema: {
        type: :object,
        required: %w[name server_id],
        properties: {
          name: { type: :string },
          server_id: { type: :string, description: "Server UUID or name" },
          deploy_branch: { type: :string, default: "main" },
          box_size: { type: :string, description: "Bundle v2 size; only when shared add-ons are enabled" },
          resources: { type: :object, description: "Per-process resources (resource-builder mode)" },
          enabled_shared_engines: { type: :array, items: { type: :string } },
          dedicated_db_engine: { type: :string, enum: %w[postgres mysql mongodb] },
          add_dedicated_redis: { type: :boolean }
        }
      }

      response "201", "app created" do
        let(:payload) { { name: "contract-new", server_id: servers(:one).id } }
        schema app_detail
        run_test!
      end

      response "401", "missing or invalid token" do
        let(:Authorization) { nil }
        let(:payload) { { name: "contract-new", server_id: servers(:one).id } }
        schema error
        run_test!
      end

      response "402", "app limit of the plan reached" do
        before { allow(Wokku.config.plan_enforcer).to receive(:quota).and_return(0) }
        let(:payload) { { name: "contract-new", server_id: servers(:one).id } }
        schema error
        run_test!
      end

      response "422", "invalid name" do
        let(:payload) { { name: "Not A Valid Name!", server_id: servers(:one).id } }
        schema error
        run_test!
      end
    end
  end

  path "/api/v1/apps/{id}" do
    parameter id_param

    get "Show an app" do
      operationId "apps.show"
      tags "apps"
      security [ { bearer: [] } ]
      produces "application/json"

      response "200", "app" do
        let(:id) { app_record.id }
        schema app_detail
        run_test! { |response| expect(JSON.parse(response.body)).not_to include("github_webhook_secret", "git_webhook_secret") }
      end

      response "401", "missing or invalid token" do
        let(:id) { app_record.id }
        let(:Authorization) { nil }
        schema error
        run_test!
      end

      response "404", "unknown app, or an app of a team the caller does not belong to" do
        let(:id) { foreign_app.id }
        schema error
        run_test!
      end
    end

    [ [ :patch, "apps.update", "Update an app (deploy_branch; a changed name renames it)" ],
      [ :put, "apps.replace", "Update an app (same as PATCH)" ] ].each do |verb, op_id, summary|
      send(verb, summary) do
        operationId op_id
        tags "apps"
        security [ { bearer: [] } ]
        consumes "application/json"
        produces "application/json"
        parameter name: :payload, in: :body, schema: {
          type: :object,
          properties: { name: { type: :string }, deploy_branch: { type: :string } }
        }

        response "200", "updated app" do
          let(:id) { app_record.id }
          let(:payload) { { deploy_branch: "release" } }
          schema app_ref
          run_test! { |response| expect(JSON.parse(response.body)["deploy_branch"]).to eq("release") }
        end

        response "400", "rename refused" do
          let(:id) { app_record.id }
          let(:payload) { { name: "taken-name" } }
          before do
            allow_any_instance_of(::Apps::Lifecycle::Renamer).to receive(:call!)
              .and_raise(::Apps::Lifecycle::Error.new("Invalid app name", code: :invalid_name))
          end
          schema error
          run_test!
        end

        response "404", "unknown app, or an app of a team the caller does not belong to" do
          let(:id) { foreign_app.id }
          let(:payload) { { deploy_branch: "release" } }
          schema error
          run_test!
        end
      end
    end

    delete "Destroy an app (team admin only)" do
      operationId "apps.destroy"
      tags "apps"
      security [ { bearer: [] } ]
      produces "application/json"
      before { allow(::Apps::Destroyer).to receive(:call).and_return(double(warnings: [])) }

      response "200", "app destroyed" do
        let(:id) { app_record.id }
        schema type: :object, required: %w[message warnings],
               properties: { message: { type: :string }, warnings: { type: :array, items: { type: :string } } }
        run_test!
      end

      response "404", "unknown app, or an app of a team the caller does not belong to" do
        let(:id) { foreign_app.id }
        schema error
        run_test!
      end
    end
  end
end

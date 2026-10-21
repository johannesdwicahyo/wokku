# frozen_string_literal: true

require "openapi_helper"

RSpec.describe "API v1 add-ons", type: :request do
  let(:user) { users(:one) }
  let(:Authorization) { "Bearer #{api_v1_token_for(user)}" }
  let(:app_record) { app_records(:one) }
  let(:foreign_app) { app_records(:two) }
  let(:viewer) { create(:user).tap { |u| create(:team_membership, user: u, team: app_record.team, role: :viewer) } }
  let(:viewer_auth) { "Bearer #{api_v1_token_for(viewer)}" }
  error = { "$ref" => "#/components/schemas/Error" }
  # Ad-hoc bodies (no error_code): {error} only.
  adhoc_error = { type: :object, required: %w[error], properties: { error: { type: :string } } }
  app_param = { name: :app_id, in: :path, schema: { type: :string }, description: "App UUID or name" }
  message_schema = { type: :object, required: %w[message], properties: { message: { type: :string } } }
  engine_body = { type: :object, required: %w[engine], properties: { engine: { type: :string, example: "redis" } } }

  path "/api/v1/apps/{app_id}/addons" do
    parameter app_param

    get "List the app's add-ons (databases)" do
      operationId "addons.list"
      tags "addons"
      security [ { bearer: [] } ]
      produces "application/json"

      response "200", "add-ons" do
        let(:app_id) { app_record.id }
        before do
          db = app_record.server.database_services.create!(name: "myapp-postgres", service_type: "postgres", status: :running)
          app_record.app_databases.create!(database_service: db, alias_name: "DATABASE")
        end
        schema type: :array, items: {
          type: :object, required: %w[id name service_type status server shared],
          properties: {
            id: { type: :string, format: :uuid }, name: { type: :string }, service_type: { type: :string },
            status: { type: :string }, server: { type: :string, description: "server name" },
            shared: { type: :boolean }, tier_name: { type: :string, nullable: true }
          }
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

    post "Create an add-on (retired: use addons.enable_shared / addons.upgrade_dedicated)" do
      operationId "addons.create"
      tags "addons"
      deprecated true
      security [ { bearer: [] } ]
      produces "application/json"

      response "410", "endpoint retired under Bundle v2" do
        let(:app_id) { app_record.id }
        schema type: :object, required: %w[error deprecated replacements],
               properties: { error: { type: :string }, deprecated: { type: :boolean },
                             replacements: { type: :object, additionalProperties: { type: :string } } }
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
  end

  path "/api/v1/apps/{app_id}/addons/{id}" do
    parameter app_param
    parameter name: :id, in: :path, schema: { type: :string }, description: "Add-on (database) UUID or name; must be linked to this app"

    delete "Destroy an add-on (farewell snapshot + teardown)" do
      operationId "addons.destroy"
      tags "addons"
      security [ { bearer: [] } ]
      produces "application/json"
      let(:app_id) { app_record.id }
      let(:db) do
        app_record.server.database_services.create!(name: "myapp-postgres", service_type: "postgres", status: :running, wokkud_managed: true)
          .tap { |d| app_record.app_databases.create!(database_service: d, alias_name: "DATABASE") }
      end
      let(:id) { db.id }

      response "200", "add-on removed" do
        before { allow(Services::Ops).to receive(:issue_and_wait!) }
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

      response "404", "unknown add-on, an add-on not linked to this app, or an app of another team" do
        let(:id) { database_services(:two).id }
        schema error
        run_test!
      end
    end
  end

  path "/api/v1/apps/{app_id}/addons/shared" do
    parameter app_param

    post "Enable a shared engine on the app (provisioning queued)" do
      operationId "addons.enable_shared"
      tags "addons"
      security [ { bearer: [] } ]
      consumes "application/json"
      produces "application/json"
      parameter name: :payload, in: :body, schema: engine_body
      let(:app_id) { app_record.id }
      let(:payload) { { engine: "redis" } }

      response "202", "engine enabled, provisioning queued" do
        before { allow_any_instance_of(Plan).to receive(:shared_engines_available).and_return(%w[postgres redis memcached]) }
        schema type: :object, required: %w[message app_id engine],
               properties: { message: { type: :string }, app_id: { type: :string, format: :uuid }, engine: { type: :string } }
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

      response "422", "unsupported engine, or the plan does not include it ({error})" do
        let(:payload) { { engine: "oracle" } }
        schema adhoc_error
        run_test!
      end
    end
  end

  path "/api/v1/apps/{app_id}/addons/shared/{engine}" do
    parameter app_param
    parameter name: :engine, in: :path, schema: { type: :string }, description: "Engine to remove (e.g. redis)"

    delete "Disable a shared engine and destroy its tenant databases" do
      operationId "addons.disable_shared"
      tags "addons"
      security [ { bearer: [] } ]
      produces "application/json"
      let(:app_id) { app_record.id }
      let(:engine) { "redis" }

      response "200", "engine removed" do
        before { allow(DatabaseProvisioner).to receive(:destroy!) }
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

      response "404", "unknown app, or an app of a team the caller does not belong to" do
        let(:app_id) { foreign_app.id }
        schema error
        run_test!
      end
    end
  end

  path "/api/v1/apps/{app_id}/addons/dedicated" do
    parameter app_param

    post "Upgrade a shared tenant to a dedicated container" do
      operationId "addons.upgrade_dedicated"
      tags "addons"
      security [ { bearer: [] } ]
      consumes "application/json"
      produces "application/json"
      parameter name: :payload, in: :body, schema: { type: :object, required: %w[engine], properties: { engine: { type: :string, example: "postgres" } } }
      let(:app_id) { app_record.id }
      let(:payload) { { engine: "postgres" } }

      response "202", "upgrade queued" do
        before { allow(DatabaseServiceUpgrade).to receive(:call).and_return(instance_double(DatabaseService, id: SecureRandom.uuid)) }
        schema type: :object, required: %w[message dedicated_id],
               properties: { message: { type: :string }, dedicated_id: { type: :string, format: :uuid } }
        run_test!
      end

      response "401", "missing or invalid token" do
        let(:Authorization) { nil }
        schema error
        run_test!
      end

      response "403", "viewer on the team, or the plan has no dedicated slots ({error})" do
        before { allow(DatabaseServiceUpgrade).to receive(:call).and_raise(UpgradeError::PlanNoSlots.new(engine: "postgres")) }
        schema oneOf: [ error, adhoc_error ]
        run_test!
      end

      response "404", "unknown app / another team's app, or no shared tenant of that engine to upgrade ({error})" do
        before { allow(DatabaseServiceUpgrade).to receive(:call).and_raise(UpgradeError::NoSharedTenant.new(engine: "postgres")) }
        schema oneOf: [ error, adhoc_error ]
        run_test!
      end

      response "422", "unsupported engine, no free slots, size cap exceeded or over account limit ({error})" do
        let(:payload) { { engine: "oracle" } }
        schema adhoc_error
        run_test!
      end
    end
  end
end

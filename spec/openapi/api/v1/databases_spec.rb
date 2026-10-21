# frozen_string_literal: true

require "openapi_helper"

# NOTE: the Database schema includes `dsn` (connection URL with credentials) —
# returned to any team member; documented as-is (see Task 6 report).
RSpec.describe "API v1 databases", type: :request do
  let(:user) { users(:one) }
  let(:Authorization) { "Bearer #{api_v1_token_for(user)}" }
  let(:server) { servers(:one) }
  let(:database) { database_services(:one) }
  let(:foreign_db) { database_services(:two) }
  let(:app_record) { app_records(:one) }
  let(:foreign_app) { app_records(:two) }
  let(:viewer) { create(:user).tap { |u| create(:team_membership, user: u, team: teams(:one), role: :viewer) } }
  error = { "$ref" => "#/components/schemas/Error" }
  adhoc_error = { type: :object, required: %w[error], properties: { error: { type: :string } } }
  db_schema = { "$ref" => "#/components/schemas/Database" }
  id_param = { name: :id, in: :path, schema: { type: :string, format: :uuid }, description: "Database UUID or name" }
  message_schema = { type: :object, required: %w[message], properties: { message: { type: :string } } }
  app_database = {
    type: :object, required: %w[id app_record_id database_service_id alias_name],
    properties: {
      id: { type: :string, format: :uuid }, app_record_id: { type: :string, format: :uuid },
      database_service_id: { type: :string, format: :uuid }, alias_name: { type: :string, example: "DATABASE" },
      created_at: { type: :string, format: "date-time" }, updated_at: { type: :string, format: "date-time" }
    }
  }

  before { allow(Apps::Restarter).to receive(:restart) }

  path "/api/v1/databases" do
    get "List databases visible to the caller" do
      operationId "databases.list"
      tags "databases"
      security [ { bearer: [] } ]
      produces "application/json"

      response "200", "databases" do
        schema type: :array, items: db_schema
        run_test!
      end

      response "401", "missing or invalid token" do
        let(:Authorization) { nil }
        schema error
        run_test!
      end
    end

    post "Provision a database" do
      operationId "databases.create"
      tags "databases"
      security [ { bearer: [] } ]
      consumes "application/json"
      produces "application/json"
      parameter name: :payload, in: :body, schema: {
        type: :object, required: %w[server_id name service_type],
        properties: {
          server_id: { type: :string, description: "Server UUID or name" },
          name: { type: :string }, service_type: { type: :string, example: "postgres" },
          tier_name: { type: :string, description: "Resource tier (default per engine)" }
        }
      }
      let(:payload) { { server_id: server.id, name: "new-pg", service_type: "postgres" } }

      response "201", "database provisioned" do
        before { allow(Services::Ops).to receive(:issue_and_wait!) }
        schema db_schema
        run_test!
      end

      response "401", "missing or invalid token" do
        let(:Authorization) { nil }
        schema error
        run_test!
      end

      response "402", "deposit does not cover one day of usage ({error, url, current_balance, required_one_day})" do
        before { allow(Wokku.config.plan_enforcer).to receive(:deposit_shortfall).and_return({ balance: 0, required: 100 }) }
        schema type: :object, required: %w[error url],
               properties: { error: { type: :string }, url: { type: :string }, current_balance: {}, required_one_day: {} }
        run_test!
      end

      response "404", "unknown server" do
        let(:payload) { { server_id: "no-such-server", name: "new-pg", service_type: "postgres" } }
        schema error
        run_test!
      end

      response "422", "engine not supported on this server (validation_failed)" do
        let(:payload) { { server_id: server.id, name: "new-cache", service_type: "memcached" } }
        schema error
        run_test!
      end

      response "502", "the host agent failed to create the service (service_create_failed)" do
        before do
          op = instance_double(ServiceOp, kind: "service.create", error: "image pull failed", error_code: "create_failed")
          allow(Services::Ops).to receive(:issue_and_wait!).and_raise(Services::Ops::Failed.new(op))
        end
        schema error
        run_test!
      end

      response "503", "the host agent did not finish in time (service_op_timeout)" do
        before { allow(Services::Ops).to receive(:issue_and_wait!).and_raise(Services::Ops::Timeout, "not finished after 300s") }
        schema error
        run_test!
      end
    end
  end

  path "/api/v1/databases/{id}" do
    parameter id_param

    get "Show a database" do
      operationId "databases.show"
      tags "databases"
      security [ { bearer: [] } ]
      produces "application/json"
      let(:id) { database.id }

      response "200", "database" do
        schema db_schema
        run_test!
      end

      response "401", "missing or invalid token" do
        let(:Authorization) { nil }
        schema error
        run_test!
      end

      response "404", "unknown database, or one the caller's teams cannot see" do
        let(:id) { foreign_db.id }
        schema error
        run_test!
      end
    end

    delete "Destroy a database (farewell snapshot, teardown, unlink)" do
      operationId "databases.destroy"
      tags "databases"
      security [ { bearer: [] } ]
      produces "application/json"
      let(:id) { database.id }

      response "200", "database destroyed" do
        before { allow(Services::Ops).to receive(:issue_and_wait!) }
        schema message_schema
        run_test!
      end

      response "401", "missing or invalid token" do
        let(:Authorization) { nil }
        schema error
        run_test!
      end

      response "403", "caller can see the database but is not a team admin" do
        let(:Authorization) { "Bearer #{api_v1_token_for(viewer)}" }
        schema error
        run_test!
      end

      response "404", "unknown database, or one the caller's teams cannot see" do
        let(:id) { foreign_db.id }
        schema error
        run_test!
      end
    end
  end

  path "/api/v1/databases/{id}/monitor" do
    parameter id_param

    get "Latest database stats snapshot" do
      operationId "databases.monitor"
      tags "databases"
      security [ { bearer: [] } ]
      produces "application/json"
      let(:id) { database.id }

      response "200", "stats (all values null until a snapshot has been collected)" do
        schema type: :object, required: %w[database_id top_queries],
               properties: {
                 database_id: { type: :string, format: :uuid },
                 recorded_at: { type: :string, format: "date-time", nullable: true },
                 active_connections: { type: :integer, nullable: true },
                 max_connections: { type: :integer, nullable: true },
                 db_size_bytes: { type: :integer, nullable: true },
                 cache_hit_ratio: { type: :number, nullable: true },
                 top_queries: { type: :array, items: { type: :object } }
               }
        run_test!
      end

      response "401", "missing or invalid token" do
        let(:Authorization) { nil }
        schema error
        run_test!
      end

      response "404", "unknown database, or one the caller's teams cannot see" do
        let(:id) { foreign_db.id }
        schema error
        run_test!
      end
    end
  end

  path "/api/v1/databases/{id}/import" do
    parameter id_param

    post "Import a dump (raw request body, e.g. pg_dump -Fc)" do
      operationId "databases.import"
      tags "databases"
      security [ { bearer: [] } ]
      consumes "application/octet-stream"
      produces "application/json"
      parameter name: :payload, in: :body, schema: { type: :string, format: :binary }
      let(:id) { database.id }
      let(:payload) { "fake-dump-bytes" }

      response "200", "dump imported" do
        before { allow(ImportService).to receive(:new).and_return(instance_double(ImportService, perform!: true)) }
        schema type: :object, required: %w[message database], properties: { message: { type: :string }, database: { type: :string } }
        run_test!
      end

      response "401", "missing or invalid token" do
        let(:Authorization) { nil }
        schema error
        run_test!
      end

      response "404", "unknown database, or one the caller's teams cannot see" do
        let(:id) { foreign_db.id }
        schema error
        run_test!
      end

      response "422", "empty body, unsupported engine, or the import failed ({error})" do
        let(:payload) { "" }
        schema adhoc_error
        run_test!
      end
    end
  end

  path "/api/v1/databases/{id}/link" do
    parameter id_param

    post "Link a database to an app (writes <ALIAS>_URL env, restarts)" do
      operationId "databases.link"
      tags "databases"
      security [ { bearer: [] } ]
      consumes "application/json"
      produces "application/json"
      parameter name: :payload, in: :body, schema: {
        type: :object, required: %w[app_id],
        properties: { app_id: { type: :string, description: "App UUID or name" }, alias_name: { type: :string, example: "DATABASE" } }
      }
      let(:linkable) { server.database_services.create!(name: "linkable-pg", service_type: "postgres", status: :running, dsn: "postgres://user:pass@host:5432/db") }
      let(:id) { linkable.id }
      let(:payload) { { app_id: app_record.id, alias_name: "PRIMARY" } }

      response "201", "linked" do
        schema app_database
        run_test!
      end

      response "401", "missing or invalid token" do
        let(:Authorization) { nil }
        schema error
        run_test!
      end

      response "404", "unknown database/app, or one the caller's teams cannot see" do
        let(:payload) { { app_id: foreign_app.id } }
        schema error
        run_test!
      end

      response "422", "database already linked to this app (validation_failed)" do
        let(:id) { database.id }
        schema error
        run_test!
      end
    end
  end

  path "/api/v1/databases/{id}/unlink" do
    parameter id_param

    post "Unlink a database from an app (unsets <ALIAS>_URL, restarts)" do
      operationId "databases.unlink"
      tags "databases"
      security [ { bearer: [] } ]
      consumes "application/json"
      produces "application/json"
      parameter name: :payload, in: :body, schema: {
        type: :object, required: %w[app_id], properties: { app_id: { type: :string, description: "App UUID or name" } }
      }
      let(:id) { database.id }
      let(:payload) { { app_id: app_record.id } }

      response "200", "unlinked" do
        before { AppDatabase.find_or_create_by!(app_record: app_record, database_service: database) { |l| l.alias_name = "DATABASE" } }
        schema message_schema
        run_test!
      end

      response "401", "missing or invalid token" do
        let(:Authorization) { nil }
        schema error
        run_test!
      end

      response "404", "unknown database/app, no such link, or one the caller's teams cannot see" do
        let(:id) { foreign_db.id }
        schema error
        run_test!
      end
    end
  end
end

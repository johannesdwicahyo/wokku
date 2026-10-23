# frozen_string_literal: true

require "openapi_helper"

# Servers are platform infrastructure shared by every tenant:
# ServerPolicy::Scope is `scope.all`, so there is no "another team's server"
# 404 - any signed-in user can list/show every server (deploy target picker).
# Mutations and status are admin-only (403 for everyone else).
RSpec.describe "API v1 servers", type: :request do
  let(:admin) { users(:admin) }
  let(:user) { users(:one) }
  let(:Authorization) { "Bearer #{api_v1_token_for(admin)}" }
  let(:user_auth) { "Bearer #{api_v1_token_for(user)}" }
  let(:server) { servers(:one) }
  error = { "$ref" => "#/components/schemas/Error" }
  server_schema = { "$ref" => "#/components/schemas/Server" }
  id_param = { name: :id, in: :path, schema: { type: :string }, description: "Server UUID or name" }
  server_summary = { "$ref" => "#/components/schemas/ServerSummary" }

  path "/api/v1/servers" do
    get "List servers" do
      operationId "servers.list"
      tags "servers"
      security [ { bearer: [] } ]
      produces "application/json"

      response "200", "all platform servers (summary fields only; any signed-in user)" do
        let(:Authorization) { user_auth }
        schema type: :array, items: server_summary
        run_test!
      end

      response "401", "missing or invalid token" do
        let(:Authorization) { nil }
        schema error
        run_test!
      end
    end

    post "Add a platform server (admin only)" do
      operationId "servers.create"
      tags "servers"
      security [ { bearer: [] } ]
      consumes "application/json"
      produces "application/json"
      parameter name: :payload, in: :body, schema: {
        type: :object, required: %w[name host],
        properties: {
          name: { type: :string, example: "edge-01" }, host: { type: :string, example: "203.0.113.10" },
          port: { type: :integer, example: 22 }, ssh_user: { type: :string }, ssh_private_key: { type: :string, description: "Write-only; never returned" }
        }
      }
      let(:payload) { { name: "edge-spec", host: "203.0.113.10" } }

      response "201", "server created (ssh_private_key and ingest_token are never returned)" do
        schema server_schema
        run_test!
      end

      response "401", "missing or invalid token" do
        let(:Authorization) { nil }
        schema error
        run_test!
      end

      response "403", "caller is not a system admin" do
        let(:Authorization) { user_auth }
        schema error
        run_test!
      end

      response "422", "missing or duplicate name/host (validation_failed)" do
        let(:payload) { { name: server.name, host: "203.0.113.11" } }
        schema error
        run_test!
      end
    end
  end

  path "/api/v1/servers/{id}" do
    parameter id_param

    get "Show a server" do
      operationId "servers.show"
      tags "servers"
      security [ { bearer: [] } ]
      produces "application/json"
      let(:id) { server.id }

      response "200", "server: full Server record for system admins; ServerSummary fields only for everyone else (secrets never returned)" do
        schema anyOf: [ server_schema, server_summary ]
        run_test!
      end

      response "401", "missing or invalid token" do
        let(:Authorization) { nil }
        schema error
        run_test!
      end

      response "404", "unknown server" do
        let(:id) { SecureRandom.uuid }
        schema error
        run_test!
      end
    end

    delete "Remove a server (admin only)" do
      operationId "servers.destroy"
      tags "servers"
      security [ { bearer: [] } ]
      produces "application/json"
      let(:id) { server.id }

      response "200", "server removed" do
        schema type: :object, required: %w[message], properties: { message: { type: :string } }
        run_test!
      end

      response "401", "missing or invalid token" do
        let(:Authorization) { nil }
        schema error
        run_test!
      end

      response "403", "caller is not a system admin" do
        let(:Authorization) { user_auth }
        schema error
        run_test!
      end

      response "404", "unknown server" do
        let(:id) { SecureRandom.uuid }
        schema error
        run_test!
      end
    end
  end

  path "/api/v1/servers/{id}/status" do
    parameter id_param

    get "Server reachability from the wokkud heartbeat (admin only)" do
      operationId "servers.status"
      tags "servers"
      security [ { bearer: [] } ]
      produces "application/json"
      let(:id) { server.id }

      response "200", "status (connected = heartbeat is fresh)" do
        schema type: :object, required: %w[status connected],
               properties: { status: { type: :string, enum: %w[connected unreachable auth_failed syncing] }, connected: { type: :boolean } }
        run_test!
      end

      response "401", "missing or invalid token" do
        let(:Authorization) { nil }
        schema error
        run_test!
      end

      response "403", "caller is not a system admin" do
        let(:Authorization) { user_auth }
        schema error
        run_test!
      end

      response "404", "unknown server" do
        let(:id) { SecureRandom.uuid }
        schema error
        run_test!
      end
    end
  end

  path "/api/v1/servers/{id}/dokku" do
    parameter id_param

    post "Retired raw dokku passthrough" do
      operationId "servers.dokku"
      deprecated true
      tags "servers"
      security [ { bearer: [] } ]
      consumes "application/json"
      produces "application/json"
      parameter name: :payload, in: :body, schema: { type: :object, properties: { args: { type: :array, items: { type: :string } } } }
      let(:id) { server.id }
      let(:payload) { { args: [ "version" ] } }

      response "401", "missing or invalid token" do
        let(:Authorization) { nil }
        schema error
        run_test!
      end

      response "403", "caller is not a system admin" do
        let(:Authorization) { user_auth }
        schema error
        run_test!
      end

      response "404", "unknown server" do
        let(:id) { SecureRandom.uuid }
        schema error
        run_test!
      end

      response "410", "passthrough_retired - always returned for admins" do
        schema error
        run_test!
      end
    end
  end
end

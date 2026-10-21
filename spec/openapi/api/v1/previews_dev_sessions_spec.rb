# frozen_string_literal: true

require "openapi_helper"

RSpec.describe "API v1 previews and dev sessions", type: :request do
  let(:user) { users(:one) }
  let(:Authorization) { "Bearer #{api_v1_token_for(user)}" }
  let(:app_record) { app_records(:one) }
  let(:foreign_app) { app_records(:two) }
  let(:viewer) { create(:user).tap { |u| create(:team_membership, user: u, team: app_record.team, role: :viewer) } }
  error = { "$ref" => "#/components/schemas/Error" }
  app_param = { name: :app_id, in: :path, schema: { type: :string }, description: "App UUID or name" }

  def make_preview(pr_number)
    app_record.preview_apps.create!(
      name: "pr-#{pr_number}-#{app_record.name}"[0, 60], server: app_record.server, team: app_record.team,
      created_by_id: app_record.team.users.first.id, pr_number: pr_number, deploy_branch: "feat/x",
      is_preview: true, status: :running
    )
  end

  # --- previews -----------------------------------------------------------
  path "/api/v1/apps/{app_id}/previews" do
    parameter app_param

    get "List the app's PR preview apps, highest PR first" do
      operationId "previews.list"
      tags "previews"
      security [ { bearer: [] } ]
      produces "application/json"

      response "200", "previews" do
        let(:app_id) { make_preview(7).parent_app_id }
        schema type: :array, items: {
          type: :object, required: %w[id name pr_number status],
          properties: {
            id: { type: :string, format: :uuid }, name: { type: :string }, pr_number: { type: :integer },
            branch: { type: :string, nullable: true }, status: { type: :string }, url: { type: :string, nullable: true }
          }
        }
        run_test! { |response| expect(JSON.parse(response.body).map { |p| p["pr_number"] }).to eq([ 7 ]) }
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

  path "/api/v1/apps/{app_id}/previews/{pr_number}" do
    parameter app_param
    parameter name: :pr_number, in: :path, schema: { type: :integer }

    delete "Destroy a PR preview (queued)" do
      operationId "previews.destroy"
      tags "previews"
      security [ { bearer: [] } ]
      produces "application/json"

      let(:app_id) { app_record.id }
      let(:pr_number) { 42 }

      response "202", "destroy queued" do
        before { make_preview(42) }
        schema type: :object, required: %w[message], properties: { message: { type: :string } }
        run_test!
      end

      response "401", "missing or invalid token" do
        let(:Authorization) { nil }
        schema error
        run_test!
      end

      response "403", "caller is a viewer (needs member or admin)" do
        let(:Authorization) { "Bearer #{api_v1_token_for(viewer)}" }
        schema error
        run_test!
      end

      response "404", "no preview with that PR number, or an app of a team the caller does not belong to" do
        schema error
        run_test!
      end
    end
  end

  # --- dev sessions -------------------------------------------------------
  path "/api/v1/apps/{app_id}/dev_sessions" do
    parameter app_param

    post "Open a time-boxed dev session (SSH + DB tunnel target)" do
      operationId "dev_sessions.create"
      tags "dev_sessions"
      security [ { bearer: [] } ]
      consumes "application/json"
      produces "application/json"
      parameter name: :payload, in: :body, schema: {
        type: :object, properties: { duration_min: { type: :integer, default: 30 } }
      }

      let(:app_id) { app_record.id }
      let(:payload) { { duration_min: 30 } }
      let(:session_double) do
        instance_double(::DevSession, id: SecureRandom.uuid, ssh_principal: "p", db_remote_host: "h",
                                      db_remote_port: 5432, read_only: true, expires_at: 30.minutes.from_now)
      end
      let(:issuer) { instance_double(::Apps::DevSession::Issuer, call!: session_double) }
      before { allow(::Apps::DevSession::Issuer).to receive(:new).and_return(issuer) }

      response "201", "session created" do
        schema type: :object,
               required: %w[session_id ssh_host ssh_port ssh_user ssh_principal db_remote_host db_remote_port local_port_suggestion readonly expires_at],
               properties: {
                 session_id: { type: :string, format: :uuid }, ssh_host: { type: :string }, ssh_port: { type: :integer },
                 ssh_user: { type: :string }, ssh_principal: { type: :string },
                 db_remote_host: { type: :string, nullable: true }, db_remote_port: { type: :integer, nullable: true },
                 local_port_suggestion: { type: :integer }, readonly: { type: :boolean },
                 expires_at: { type: :string, format: "date-time" }
               }
        run_test! { |response| expect(JSON.parse(response.body)["ssh_host"]).to eq(app_record.server.host) }
      end

      response "401", "missing or invalid token" do
        let(:Authorization) { nil }
        schema error
        run_test!
      end

      response "403", "caller is a viewer (needs member or admin)" do
        let(:Authorization) { "Bearer #{api_v1_token_for(viewer)}" }
        schema error
        run_test!
      end

      response "404", "unknown app, or an app of a team the caller does not belong to" do
        let(:app_id) { foreign_app.id }
        schema error
        run_test!
      end

      response "409", "app container not running (app_not_running)" do
        before { allow(issuer).to receive(:call!).and_raise(::Apps::DevSession::Error.new("Could not resolve IP", code: :container_not_found)) }
        schema error
        run_test!
      end

      response "422", "no database to tunnel to (validation_failed)" do
        before { allow(issuer).to receive(:call!).and_raise(::Apps::DevSession::Error.new("no postgres", code: :no_postgres)) }
        schema error
        run_test!
      end
    end
  end

  path "/api/v1/apps/{app_id}/dev_sessions/{id}" do
    parameter app_param
    parameter name: :id, in: :path, schema: { type: :string, format: :uuid }

    delete "Revoke a dev session (idempotent)" do
      operationId "dev_sessions.destroy"
      tags "dev_sessions"
      security [ { bearer: [] } ]
      produces "application/json"

      let(:app_id) { app_record.id }
      let(:id) { SecureRandom.uuid }

      response "204", "revoked, or already gone" do
        run_test!
      end

      response "401", "missing or invalid token" do
        let(:Authorization) { nil }
        schema error
        run_test!
      end

      response "403", "caller is a viewer (needs member or admin)" do
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

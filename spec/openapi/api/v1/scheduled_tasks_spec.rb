# frozen_string_literal: true

require "openapi_helper"

RSpec.describe "API v1 scheduled tasks", type: :request do
  let(:user) { users(:one) }
  let(:Authorization) { "Bearer #{api_v1_token_for(user)}" }
  let(:app_record) { app_records(:one) }
  let(:foreign_app) { app_records(:two) }
  let(:viewer) { create(:user).tap { |u| create(:team_membership, user: u, team: app_record.team, role: :viewer) } }
  let(:viewer_auth) { "Bearer #{api_v1_token_for(viewer)}" }
  error = { "$ref" => "#/components/schemas/Error" }
  app_param = { name: :app_id, in: :path, schema: { type: :string }, description: "App UUID or name" }
  task_schema = {
    type: :object, required: %w[id command schedule enabled created_at],
    properties: {
      id: { type: :string, format: :uuid }, command: { type: :string, example: "bin/rails cleanup" },
      schedule: { type: :string, description: "cron expression", example: "*/5 * * * *" },
      description: { type: :string, nullable: true }, enabled: { type: :boolean },
      created_at: { type: :string, format: "date-time" }
    }
  }
  let(:plan_ok) { allow_any_instance_of(User).to receive(:plan).and_return(instance_double("Plan", "has_feature?": true)) }

  path "/api/v1/apps/{app_id}/scheduled_tasks" do
    parameter app_param

    get "List the app's scheduled (cron) tasks" do
      operationId "scheduled_tasks.list"
      tags "scheduled_tasks"
      security [ { bearer: [] } ]
      produces "application/json"

      response "200", "tasks ordered by schedule" do
        let(:app_id) { app_record.id }
        before { app_record.scheduled_tasks.create!(command: "ls", schedule: "*/5 * * * *", description: "Tick") }
        schema type: :array, items: task_schema
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

    post "Create a scheduled task (Pro plan feature)" do
      operationId "scheduled_tasks.create"
      tags "scheduled_tasks"
      security [ { bearer: [] } ]
      consumes "application/json"
      produces "application/json"
      parameter name: :payload, in: :body, schema: {
        type: :object, required: %w[command schedule],
        properties: { command: { type: :string }, schedule: { type: :string, example: "*/5 * * * *" }, description: { type: :string } }
      }
      let(:app_id) { app_record.id }
      let(:payload) { { command: "ls", schedule: "*/5 * * * *" } }
      let(:creator) { instance_double(::Apps::Cron::TaskCreator) }
      before { allow(::Apps::Cron::TaskCreator).to receive(:new).and_return(creator) }

      response "201", "task created" do
        before do
          plan_ok
          allow(creator).to receive(:call!).and_return(
            app_record.scheduled_tasks.create!(command: "ls", schedule: "*/5 * * * *")
          )
        end
        schema task_schema
        run_test!
      end

      response "400", "invalid schedule or command (invalid_params)" do
        before { plan_ok }
        before { allow(creator).to receive(:call!).and_raise(::Apps::Cron::Error.new("Schedule is not valid cron", code: :invalid)) }
        schema error
        run_test!
      end

      response "401", "missing or invalid token" do
        let(:Authorization) { nil }
        schema error
        run_test!
      end

      response "403", "plan lacks scheduled tasks ({error, upgrade_url}); a viewer on the team gets the standard Error body" do
        before { allow_any_instance_of(User).to receive(:plan).and_return(instance_double("Plan", "has_feature?": false)) }
        schema oneOf: [ error, { type: :object, required: %w[error upgrade_url], properties: { error: { type: :string }, upgrade_url: { type: :string } } } ]
        run_test!
      end

      response "404", "unknown app, or an app of a team the caller does not belong to" do
        let(:app_id) { foreign_app.id }
        schema error
        run_test!
      end

      response "502", "the host failed to apply the cron change (dokku_command_failed)" do
        before { plan_ok }
        before { allow(creator).to receive(:call!).and_raise(::Apps::Cron::Error.new("cron plugin failed", code: :dokku_error)) }
        schema error
        run_test!
      end
    end
  end

  path "/api/v1/apps/{app_id}/scheduled_tasks/{id}" do
    parameter app_param
    parameter name: :id, in: :path, schema: { type: :string, format: :uuid }

    delete "Delete a scheduled task" do
      operationId "scheduled_tasks.destroy"
      tags "scheduled_tasks"
      security [ { bearer: [] } ]
      produces "application/json"
      let(:app_id) { app_record.id }
      let(:id) { app_record.scheduled_tasks.create!(command: "ls", schedule: "*/5 * * * *").id }
      before { allow(::Apps::Cron::TaskDestroyer).to receive(:new).and_return(instance_double(::Apps::Cron::TaskDestroyer, call!: true)) }

      response "204", "task deleted" do
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

      response "404", "unknown task, or an app of a team the caller does not belong to" do
        let(:app_id) { foreign_app.id }
        schema error
        run_test!
      end

      response "502", "the host failed to remove the cron entry (dokku_command_failed)" do
        before { allow(::Apps::Cron::TaskDestroyer).to receive(:new).and_return(instance_double(::Apps::Cron::TaskDestroyer).tap { |d| allow(d).to receive(:call!).and_raise(::Apps::Cron::Error.new("cron plugin failed", code: :dokku_error)) }) }
        schema error
        run_test!
      end
    end
  end
end

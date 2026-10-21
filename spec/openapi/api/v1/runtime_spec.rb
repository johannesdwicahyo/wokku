# frozen_string_literal: true

require "openapi_helper"

# ps, runs, logs, checks, doctor.
RSpec.describe "API v1 runtime", type: :request do
  let(:user) { users(:one) }
  let(:Authorization) { "Bearer #{api_v1_token_for(user)}" }
  let(:app_record) { app_records(:one) }
  let(:foreign_app) { app_records(:two) }
  let(:viewer) { create(:user).tap { |u| create(:team_membership, user: u, team: app_record.team, role: :viewer) } }
  error = { "$ref" => "#/components/schemas/Error" }
  app_param = { name: :app_id, in: :path, schema: { type: :string }, description: "App UUID or name" }
  scaling_body = {
    type: :object,
    properties: {
      scaling: { type: :object, additionalProperties: { type: :integer }, description: "process type => count" },
      resources: { type: :object, additionalProperties: { type: :object }, description: "process type => shape (cpu/memory/count)" }
    }
  }

  # --- ps -----------------------------------------------------------------
  path "/api/v1/apps/{app_id}/ps" do
    parameter app_param

    get "Process (Swarm task) states from the latest host heartbeat" do
      operationId "ps.show"
      tags "ps"
      security [ { bearer: [] } ]
      produces "application/json"

      response "200", "process report" do
        let(:app_id) { app_record.id }
        before { app_record.update!(live_containers: [ { "process" => "web", "state" => "running" } ]) }
        schema "$ref" => "#/components/schemas/Process"
        run_test! { |response| expect(JSON.parse(response.body)["processes"]).to eq("status_web_1" => "running") }
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

    [ [ :patch, "ps.update", "Scale processes (counts and/or resources)" ],
      [ :put, "ps.replace", "Scale processes (same as PATCH)" ] ].each do |verb, op_id, summary|
      send(verb, summary) do
        operationId op_id
        tags "ps"
        security [ { bearer: [] } ]
        consumes "application/json"
        produces "application/json"
        parameter name: :payload, in: :body, schema: scaling_body

        let(:app_id) { app_record.id }
        let(:payload) { { scaling: { web: 2 } } }
        message_schema = { type: :object, required: %w[message], properties: { message: { type: :string } } }

        response "200", "scaling applied" do
          before do
            user.plan.update!(box_quotas: { "small" => 10 })
            allow(::Lifecycle::Ops).to receive(:converge!)
          end
          schema message_schema
          run_test!
        end

        response "400", "scaling parameter missing (invalid_params)" do
          let(:payload) { {} }
          schema error
          run_test!
        end

        response "401", "missing or invalid token" do
          let(:Authorization) { nil }
          schema error
          run_test!
        end

        response "402", "account suspended for an unpaid invoice (account_suspended)" do
          before { allow_any_instance_of(AppRecord).to receive(:run_allowed?).and_return(false) }
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

        response "409", "another operation holds the app (service_busy, retryable)" do
          before do
            user.plan.update!(box_quotas: { "small" => 10 })
            allow(::Lifecycle::Ops).to receive(:converge!).and_raise(::Lifecycle::Ops::Busy.new(app_record))
          end
          schema error
          run_test!
        end

        response "422", "formation_would_empty, or quota_exceeded for the plan" do
          before { allow(::Lifecycle::Ops).to receive(:converge!).and_raise(::Lifecycle::Ops::EmptyFormation, "formation omits web") }
          let(:payload) { { scaling: { worker: 1 } } }
          schema error
          run_test!
        end

        response "502", "the host failed to converge (dokku_command_failed)" do
          before do
            user.plan.update!(box_quotas: { "small" => 10 })
            op = LifecycleOp.new(kind: "stack.converge", error: "boom", error_code: "task_failed")
            allow(::Lifecycle::Ops).to receive(:converge!).and_raise(::Lifecycle::Ops::Failed.new(op))
          end
          schema error
          run_test!
        end
      end
    end
  end

  # --- runs ---------------------------------------------------------------
  path "/api/v1/apps/{app_id}/runs/{id}" do
    parameter app_param
    parameter name: :id, in: :path, schema: { type: :string, format: :uuid }, description: "run_id from apps.run"

    get "Poll a one-off command started with apps.run" do
      operationId "runs.show"
      tags "runs"
      security [ { bearer: [] } ]
      produces "application/json"

      let(:app_id) { app_record.id }
      let(:op) do
        create(:lifecycle_op, app_record: app_record, server: app_record.server, kind: "stack.run",
               status: :succeeded, result: { "exit_code" => 0, "output" => "done" })
      end
      let(:id) { op.id }

      response "200", "run status and result" do
        schema type: :object, required: %w[run_id status],
               properties: {
                 run_id: { type: :string, format: :uuid },
                 status: { type: :string, enum: %w[pending claimed succeeded failed] },
                 exit_code: { type: :integer, nullable: true },
                 output: { type: :string, nullable: true },
                 error: { type: :string, nullable: true },
                 error_code: { type: :string, nullable: true }
               }
        run_test! { |response| expect(JSON.parse(response.body)).to include("status" => "succeeded", "exit_code" => 0, "output" => "done") }
      end

      response "401", "missing or invalid token" do
        let(:Authorization) { nil }
        schema error
        run_test!
      end

      response "404", "unknown run, or an app of a team the caller does not belong to" do
        let(:app_id) { foreign_app.id }
        schema error
        run_test!
      end
    end
  end

  # --- logs ---------------------------------------------------------------
  path "/api/v1/apps/{app_id}/logs" do
    parameter app_param

    get "Recent logs (JSON); with follow=1 a live text/plain stream" do
      operationId "logs.list"
      tags "logs"
      security [ { bearer: [] } ]
      produces "application/json" # errors are always JSON; the follow stream is added on the 200 below
      parameter name: :follow, in: :query, required: false, schema: { type: :string, enum: %w[1 true] },
                description: "1/true switches to a chunked text/plain stream of live log output"
      parameter name: :since, in: :query, required: false, schema: { type: :string, format: "date-time" }
      parameter name: :until, in: :query, required: false, schema: { type: :string, format: "date-time" }
      parameter name: :lines, in: :query, required: false, schema: { type: :integer, minimum: 1, maximum: 1000, default: 100 }
      parameter name: :level, in: :query, required: false, schema: { type: :string }
      parameter name: :q, in: :query, required: false, schema: { type: :string }, description: "Substring filter"

      let(:app_id) { app_record.id }
      log_result = {
        type: :object, required: %w[logs source],
        properties: {
          logs: {
            oneOf: [
              { type: :array, items: { type: :object, required: %w[ts container level line],
                                       properties: { ts: { type: :string, format: "date-time" }, container: { type: :string },
                                                     level: { type: :string }, line: { type: :string } } } },
              { type: :string, description: "Raw tail output when source is live" }
            ]
          },
          source: { type: :string, enum: %w[durable live] }
        }
      }

      response "200", "log lines (JSON), or a text/plain stream when follow=1" do
        before do
          Log.insert_all([ { server_id: app_record.server_id, app_record_id: app_record.id, container: "web.1",
                             ts: 1.hour.ago, level: "info", line: "GET / 200", ingested_at: Time.current } ])
        end
        # rswag attaches `schema` to every `produces` type, so the follow
        # stream's text/plain media type is declared here with its own schema.
        metadata[:response][:content] = { "text/plain" => { schema: { type: :string } } }
        schema log_result
        run_test! { |response| expect(JSON.parse(response.body)["source"]).to eq("durable") }
      end

      response "502", "durable store empty and the live SSH tail failed (dokku_command_failed)" do
        before { allow_any_instance_of(Hosts::Ssh).to receive(:run_raw).and_raise(Hosts::Ssh::CommandError.new("docker failed", exit_code: 1)) }
        schema error
        run_test!
      end

      response "503", "durable store empty and the host is unreachable (host_unreachable, retryable)" do
        before { allow_any_instance_of(Hosts::Ssh).to receive(:run_raw).and_raise(Hosts::Ssh::ConnectionError, "ssh down") }
        schema error
        run_test!
      end

      response "400", "since/until not parseable (invalid_time)" do
        let(:since) { "not-a-time" }
        schema error
        run_test!
      end

      response "401", "missing or invalid token" do
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

  # --- checks -------------------------------------------------------------
  path "/api/v1/apps/{app_id}/checks" do
    parameter app_param

    get "Health-check status (platform-supervised on the Swarm runtime)" do
      operationId "checks.show"
      tags "checks"
      security [ { bearer: [] } ]
      produces "application/json"

      response "200", "supervised health" do
        let(:app_id) { app_record.id }
        schema type: :object, required: %w[checks],
               properties: {
                 checks: {
                   type: :object, required: %w[supervised runtime message],
                   properties: { supervised: { type: :boolean }, runtime: { type: :string }, message: { type: :string } }
                 }
               }
        run_test! { |response| expect(JSON.parse(response.body).dig("checks", "supervised")).to be(true) }
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

    [ [ :patch, "checks.update", "Change health checks (always refused: managed by the runtime)" ],
      [ :put, "checks.replace", "Change health checks (same as PATCH)" ] ].each do |verb, op_id, summary|
      send(verb, summary) do
        operationId op_id
        tags "checks"
        security [ { bearer: [] } ]
        consumes "application/json"
        produces "application/json"
        parameter name: :payload, in: :body, schema: { type: :object }

        let(:app_id) { app_record.id }
        let(:payload) { { enabled: true } }

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

        response "422", "refused: health checks are managed by the Swarm runtime" do
          schema error
          run_test!
        end
      end
    end
  end

  # --- doctor -------------------------------------------------------------
  path "/api/v1/doctor" do
    get "Self-diagnosis across auth, client version, hosts and apps" do
      operationId "doctor.show"
      tags "doctor"
      security [ { bearer: [] } ]
      produces "application/json"

      response "200", "report" do
        schema type: :object, required: %w[status checks hints],
               properties: {
                 status: { type: :string, enum: %w[ok issues] },
                 checks: {
                   type: :array,
                   items: { type: :object, required: %w[name status],
                            properties: { name: { type: :string, enum: %w[auth client hosts apps] },
                                          status: { type: :string, enum: %w[ok warn error] },
                                          detail: { type: :string },
                                          hosts: { type: :array, items: { type: :object } },
                                          apps: { type: :array, items: { type: :object } } } }
                 },
                 hints: { type: :array, items: { type: :string } }
               }
        run_test! { |response| expect(JSON.parse(response.body)["checks"].map { |c| c["name"] }).to include("auth", "apps") }
      end

      response "401", "missing or invalid token" do
        let(:Authorization) { nil }
        schema error
        run_test!
      end
    end
  end
end

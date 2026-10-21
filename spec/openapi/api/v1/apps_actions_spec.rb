# frozen_string_literal: true

require "openapi_helper"

RSpec.describe "API v1 app actions", type: :request do
  let(:user) { users(:one) }
  let(:Authorization) { "Bearer #{api_v1_token_for(user)}" }
  let(:app_record) { app_records(:one) }
  let(:foreign_app) { app_records(:two) }
  error = { "$ref" => "#/components/schemas/Error" }
  id_param = { name: :id, in: :path, schema: { type: :string }, description: "App UUID or name" }

  before { allow_any_instance_of(Apps::Lifecycle::DeployLock).to receive(:locked?).and_return(false) }

  # Every action documents the same 404; keeps the per-operation blocks short.
  def self.foreign_404(&body)
    response "404", "unknown app, or an app of a team the caller does not belong to" do
      let(:id) { foreign_app.id }
      instance_exec(&body) if body
      schema "$ref" => "#/components/schemas/Error"
      run_test!
    end
  end

  # --- queued process actions -------------------------------------------
  %w[restart stop start].each do |action|
    path "/api/v1/apps/{id}/#{action}" do
      parameter id_param

      post "#{action.capitalize} the app's processes (queued)" do
        operationId "apps.#{action}"
        tags "apps"
        security [ { bearer: [] } ]
        produces "application/json"

        response "202", "#{action} queued" do
          let(:id) { app_record.id }
          schema type: :object, required: %w[message app_id action],
                 properties: { message: { type: :string }, app_id: { type: :string, format: :uuid }, action: { type: :string } }
          run_test!
        end

        response "401", "missing or invalid token" do
          let(:id) { app_record.id }
          let(:Authorization) { nil }
          schema error
          run_test!
        end

        unless action == "stop"
          response "402", "account suspended for an unpaid invoice" do
            let(:id) { app_record.id }
            before { allow_any_instance_of(AppRecord).to receive(:run_allowed?).and_return(false) }
            schema error
            run_test!
          end
        end

        foreign_404
      end
    end
  end

  path "/api/v1/apps/{id}/deploy" do
    parameter id_param

    post "Trigger a deploy" do
      operationId "apps.deploy"
      tags "apps"
      security [ { bearer: [] } ]
      produces "application/json"

      response "202", "deploy queued" do
        let(:id) { app_record.id }
        schema type: :object, required: %w[message deploy_id release_id],
               properties: { message: { type: :string }, deploy_id: { type: :string, format: :uuid }, release_id: { type: :string, format: :uuid } }
        run_test!
      end

      response "409", "app is locked" do
        let(:id) { app_record.id }
        before { allow_any_instance_of(Apps::Lifecycle::DeployLock).to receive(:locked?).and_return(true) }
        schema error
        run_test!
      end

      foreign_404
    end
  end

  path "/api/v1/apps/{id}/run" do
    parameter id_param

    post "Run a one-off command (async; poll GET /apps/{app_id}/runs/{id})" do
      operationId "apps.run"
      tags "apps"
      security [ { bearer: [] } ]
      consumes "application/json"
      produces "application/json"
      parameter name: :payload, in: :body, schema: {
        type: :object, required: %w[command], properties: { command: { type: :string } }
      }

      response "202", "run queued" do
        let(:id) { app_record.id }
        let(:payload) { { command: "echo hi" } }
        before { allow(::Lifecycle::Ops).to receive(:run!).and_return(double(id: SecureRandom.uuid)) }
        schema type: :object, required: %w[run_id], properties: { run_id: { type: :string, format: :uuid } }
        run_test!
      end

      response "400", "command missing" do
        let(:id) { app_record.id }
        let(:payload) { {} }
        schema error
        run_test!
      end

      response "409", "another operation already holds the app's lane" do
        let(:id) { app_record.id }
        let(:payload) { { command: "echo hi" } }
        before { allow(::Lifecycle::Ops).to receive(:run!).and_raise(::Lifecycle::Ops::Busy.new(app_record)) }
        schema error
        run_test!
      end

      foreign_404 { let(:payload) { { command: "echo hi" } } }
    end
  end

  path "/api/v1/apps/{id}/dokku" do
    parameter id_param

    post "Retired raw passthrough (always 410)" do
      operationId "apps.dokku"
      tags "apps"
      deprecated true
      security [ { bearer: [] } ]
      produces "application/json"

      response "410", "passthrough retired; use the typed commands" do
        let(:id) { app_record.id }
        schema error
        run_test!
      end

      foreign_404
    end
  end

  # --- GitHub ----------------------------------------------------------
  path "/api/v1/apps/{id}/github_connect" do
    parameter id_param

    post "Connect a GitHub repo for deploy-on-push" do
      operationId "apps.github_connect"
      tags "apps"
      security [ { bearer: [] } ]
      consumes "application/json"
      produces "application/json"
      parameter name: :payload, in: :body, schema: {
        type: :object, required: %w[repo],
        properties: { repo: { type: :string, description: "owner/name" }, branch: { type: :string, default: "main" } }
      }

      response "200", "connected" do
        let(:id) { app_record.id }
        let(:payload) { { repo: "octo/hello", branch: "main" } }
        schema type: :object, required: %w[message app_id github_repo deploy_branch],
               properties: { message: { type: :string }, app_id: { type: :string, format: :uuid },
                             github_repo: { type: :string }, deploy_branch: { type: :string } }
        run_test!
      end

      response "422", "repo missing" do
        let(:id) { app_record.id }
        let(:payload) { {} }
        schema error
        run_test!
      end

      foreign_404 { let(:payload) { { repo: "octo/hello" } } }
    end
  end

  path "/api/v1/apps/{id}/github_disconnect" do
    parameter id_param

    delete "Disconnect the GitHub repo" do
      operationId "apps.github_disconnect"
      tags "apps"
      security [ { bearer: [] } ]
      produces "application/json"

      response "200", "disconnected" do
        let(:id) { app_record.id }
        schema type: :object, required: %w[message], properties: { message: { type: :string } }
        run_test!
      end

      foreign_404
    end
  end

  # --- settings toggles --------------------------------------------------
  {
    "https" => [ "Apps::Settings::HttpsToggle", "Enable or disable HTTPS redirect" ],
    "cdn" => [ "Apps::Settings::CdnToggle", "Enable or disable the Cloudflare CDN proxy" ],
    "maintenance" => [ "Apps::Settings::MaintenanceToggle", "Enable or disable maintenance mode" ]
  }.each do |name, (klass, summary)|
    path "/api/v1/apps/{id}/#{name}" do
      parameter id_param

      patch summary do
        operationId "apps.#{name}"
        tags "apps"
        security [ { bearer: [] } ]
        consumes "application/json"
        produces "application/json"
        parameter name: :payload, in: :body, schema: {
          type: :object, required: %w[enabled], properties: { enabled: { type: :boolean } }
        }
        before { allow(klass.constantize).to receive(:new).and_return(double(enable!: true, disable!: true)) }

        response "200", "new state" do
          let(:id) { app_record.id }
          let(:payload) { { enabled: true } }
          schema type: :object, required: %w[enabled], properties: { enabled: { type: :boolean } }
          run_test! { |response| expect(JSON.parse(response.body)).to eq("enabled" => true) }
        end

        response "422", "enabled missing" do
          let(:id) { app_record.id }
          let(:payload) { {} }
          schema error
          run_test!
        end

        response "502", "the host refused the change" do
          let(:id) { app_record.id }
          let(:payload) { { enabled: true } }
          before do
            allow(klass.constantize).to receive(:new)
              .and_return(double(enable!: nil).tap { |d| allow(d).to receive(:enable!).and_raise(::Apps::Settings::Error.new("host said no", code: :dokku_error)) })
          end
          schema error
          run_test!
        end

        foreign_404 { let(:payload) { { enabled: true } } }
      end
    end
  end

  # --- rename / clone / transfer ----------------------------------------
  path "/api/v1/apps/{id}/rename" do
    parameter id_param

    patch "Rename the app" do
      operationId "apps.rename"
      tags "apps"
      security [ { bearer: [] } ]
      consumes "application/json"
      produces "application/json"
      parameter name: :payload, in: :body, schema: {
        type: :object, required: %w[name], properties: { name: { type: :string } }
      }

      response "200", "renamed" do
        let(:id) { app_record.id }
        let(:payload) { { name: "renamed-app" } }
        before { allow_any_instance_of(::Apps::Lifecycle::Renamer).to receive(:call!).and_return(double(id: SecureRandom.uuid, name: "renamed-app", team: app_record.team)) }
        schema type: :object, required: %w[id name], properties: { id: { type: :string, format: :uuid }, name: { type: :string } }
        run_test!
      end

      response "400", "invalid name" do
        let(:id) { app_record.id }
        let(:payload) { { name: "BAD NAME" } }
        before { allow_any_instance_of(::Apps::Lifecycle::Renamer).to receive(:call!).and_raise(::Apps::Lifecycle::Error.new("Invalid app name", code: :invalid_name)) }
        schema error
        run_test!
      end

      response "409", "name taken" do
        let(:id) { app_record.id }
        let(:payload) { { name: "taken" } }
        before { allow_any_instance_of(::Apps::Lifecycle::Renamer).to receive(:call!).and_raise(::Apps::Lifecycle::Error.new("Name taken", code: :name_taken)) }
        schema error
        run_test!
      end

      foreign_404 { let(:payload) { { name: "renamed-app" } } }
    end
  end

  path "/api/v1/apps/{id}/clone" do
    parameter id_param

    post "Clone the app (config; deploy skipped by default)" do
      operationId "apps.clone"
      tags "apps"
      security [ { bearer: [] } ]
      consumes "application/json"
      produces "application/json"
      parameter name: :payload, in: :body, schema: {
        type: :object, required: %w[name],
        properties: { name: { type: :string }, skip_deploy: { type: :boolean, default: true } }
      }

      response "200", "cloned" do
        let(:id) { app_record.id }
        let(:payload) { { name: "cloned-app" } }
        before { allow_any_instance_of(::Apps::Lifecycle::Cloner).to receive(:call!).and_return(double(id: SecureRandom.uuid, name: "cloned-app")) }
        schema type: :object, required: %w[id name], properties: { id: { type: :string, format: :uuid }, name: { type: :string } }
        run_test!
      end

      response "409", "name taken" do
        let(:id) { app_record.id }
        let(:payload) { { name: "taken" } }
        before { allow_any_instance_of(::Apps::Lifecycle::Cloner).to receive(:call!).and_raise(::Apps::Lifecycle::Error.new("Name taken", code: :name_taken)) }
        schema error
        run_test!
      end

      foreign_404 { let(:payload) { { name: "cloned-app" } } }
    end
  end

  path "/api/v1/apps/{id}/transfer" do
    parameter id_param

    post "Start an ownership transfer (team admin only)" do
      operationId "apps.transfer"
      tags "apps"
      security [ { bearer: [] } ]
      consumes "application/json"
      produces "application/json"
      parameter name: :payload, in: :body, schema: {
        type: :object, required: %w[recipient_email], properties: { recipient_email: { type: :string } }
      }

      response "200", "transfer requested" do
        let(:id) { app_record.id }
        let(:payload) { { recipient_email: "to@example.com" } }
        before do
          transfer = double(id: SecureRandom.uuid, to_user: double(email: "to@example.com"), expires_at: 7.days.from_now)
          allow_any_instance_of(::Apps::Lifecycle::Transferrer).to receive(:call!).and_return(transfer)
        end
        schema type: :object, required: %w[transfer_id recipient_email expires_at],
               properties: { transfer_id: { type: :string, format: :uuid }, recipient_email: { type: :string },
                             expires_at: { type: :string, format: "date-time" } }
        run_test!
      end

      response "400", "invalid recipient" do
        let(:id) { app_record.id }
        let(:payload) { { recipient_email: "nope" } }
        before { allow_any_instance_of(::Apps::Lifecycle::Transferrer).to receive(:call!).and_raise(::Apps::Lifecycle::Error.new("Invalid email", code: :invalid_email)) }
        schema error
        run_test!
      end

      response "409", "a transfer is already pending" do
        let(:id) { app_record.id }
        let(:payload) { { recipient_email: "to@example.com" } }
        before { allow_any_instance_of(::Apps::Lifecycle::Transferrer).to receive(:call!).and_raise(::Apps::Lifecycle::Error.new("pending", code: :transfer_pending)) }
        schema error
        run_test!
      end

      foreign_404 { let(:payload) { { recipient_email: "to@example.com" } } }
    end
  end

  # --- lock / unlock -----------------------------------------------------
  { "lock" => true, "unlock" => false }.each do |name, state|
    path "/api/v1/apps/{id}/#{name}" do
      parameter id_param

      post "#{name.capitalize} deploys" do
        operationId "apps.#{name}"
        tags "apps"
        security [ { bearer: [] } ]
        produces "application/json"
        before { allow_any_instance_of(Apps::Lifecycle::DeployLock).to receive(:"#{name}!") }

        response "200", "#{name}ed" do
          let(:id) { app_record.id }
          schema type: :object, required: %w[locked], properties: { locked: { type: :boolean } }
          run_test! { |response| expect(JSON.parse(response.body)).to eq("locked" => state) }
        end

        foreign_404
      end
    end
  end

  # --- read-only telemetry ----------------------------------------------
  path "/api/v1/apps/{id}/metrics" do
    parameter id_param

    get "Recent CPU / memory samples" do
      operationId "apps.metrics"
      tags "apps"
      security [ { bearer: [] } ]
      produces "application/json"

      response "200", "metrics" do
        let(:id) { app_record.id }
        schema type: :object, required: %w[app_id minute hourly],
               properties: { app_id: { type: :string, format: :uuid },
                             minute: { type: :array, items: { type: :object } },
                             hourly: { type: :array, items: { type: :object } } }
        run_test!
      end

      foreign_404
    end
  end

  path "/api/v1/apps/{id}/monitor" do
    parameter id_param

    get "24h request monitor (totals, buckets, slowest requests)" do
      operationId "apps.monitor"
      tags "apps"
      security [ { bearer: [] } ]
      produces "application/json"

      response "200", "monitor" do
        let(:id) { app_record.id }
        schema type: :object, required: %w[app_id window_seconds totals buckets recent_slow],
               properties: { app_id: { type: :string, format: :uuid }, window_seconds: { type: :integer },
                             totals: { type: :object }, buckets: { type: :array, items: { type: :object } },
                             recent_slow: { type: :array, items: { type: :object } } }
        run_test!
      end

      foreign_404
    end
  end

  path "/api/v1/apps/{id}/vitals" do
    parameter id_param

    get "7-day web vitals rollups" do
      operationId "apps.vitals"
      tags "apps"
      security [ { bearer: [] } ]
      produces "application/json"

      response "200", "vitals" do
        let(:id) { app_record.id }
        schema type: :object, required: %w[app_id window_days latest history],
               properties: { app_id: { type: :string, format: :uuid }, window_days: { type: :integer },
                             latest: { type: :object }, history: { type: :object } }
        run_test!
      end

      foreign_404
    end
  end
end

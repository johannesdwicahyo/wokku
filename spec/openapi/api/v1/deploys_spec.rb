# frozen_string_literal: true

require "openapi_helper"

RSpec.describe "API v1 deploys", type: :request do
  let(:user) { users(:one) }
  let(:Authorization) { "Bearer #{api_v1_token_for(user)}" }
  let(:app_record) { app_records(:one) }
  let(:foreign_app) { app_records(:two) }
  let(:viewer) { create(:user).tap { |u| create(:team_membership, user: u, team: app_record.team, role: :viewer) } }
  let(:store) { instance_double(DeployArchiveStore) }
  error = { "$ref" => "#/components/schemas/Error" }
  deploy_ref = { "$ref" => "#/components/schemas/Deploy" }
  app_param = { name: :app_id, in: :path, schema: { type: :string }, description: "App UUID or name" }

  before do
    allow(Wokku.config).to receive(:backup_store).and_return(store)
    allow(::Apps::Lifecycle::DeployLock).to receive(:new)
      .and_return(instance_double(::Apps::Lifecycle::DeployLock, locked?: false))
  end

  path "/api/v1/apps/{app_id}/deploys" do
    parameter app_param

    get "List the app's 20 most recent deploys" do
      operationId "deploys.list"
      tags "deploys"
      security [ { bearer: [] } ]
      produces "application/json"

      response "200", "deploys, newest first" do
        let(:deploy) { create(:deploy, :succeeded, app_record: app_record) }
        let(:app_id) { deploy.app_record_id }
        schema type: :array, items: deploy_ref
        run_test! { |response| expect(JSON.parse(response.body).map { |d| d["id"] }).to include(deploy.id) }
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

    post "Deploy from an uploaded source tarball (see deploys.upload_url)" do
      operationId "deploys.create"
      tags "deploys"
      security [ { bearer: [] } ]
      consumes "application/json"
      produces "application/json"
      parameter name: :payload, in: :body, schema: {
        type: :object, required: %w[archive_key],
        properties: { archive_key: { type: :string, description: "deploy-archives/<app id>/<uuid>.tar.gz, as returned by deploys.upload_url" } }
      }

      let(:app_id) { app_record.id }
      let(:payload) { { archive_key: "deploy-archives/#{app_record.id}/#{SecureRandom.uuid}.tar.gz" } }

      response "202", "build queued" do
        before { allow(store).to receive(:exists?).and_return(true) }
        schema type: :object, required: %w[deploy_id status],
               properties: { deploy_id: { type: :string, format: :uuid }, status: { type: :string } }
        run_test! { |response| expect(Deploy.find(JSON.parse(response.body)["deploy_id"]).archive_key).to eq(payload[:archive_key]) }
      end

      response "400", "archive_key missing or not this app's deploy-archives key" do
        let(:payload) { { archive_key: "not-a-real-key" } }
        schema error
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

      response "409", "app is locked (app_locked)" do
        before do
          allow(::Apps::Lifecycle::DeployLock).to receive(:new)
            .and_return(instance_double(::Apps::Lifecycle::DeployLock, locked?: true))
        end
        schema error
        run_test!
      end

      response "422", "archive was never uploaded (archive_missing)" do
        before { allow(store).to receive(:exists?).and_return(false) }
        schema error
        run_test!
      end
    end
  end

  path "/api/v1/apps/{app_id}/deploys/{id}" do
    parameter app_param
    parameter name: :id, in: :path, schema: { type: :string, format: :uuid }

    get "Show a deploy, including its log" do
      operationId "deploys.show"
      tags "deploys"
      security [ { bearer: [] } ]
      produces "application/json"

      let(:deploy) { create(:deploy, :succeeded, app_record: app_record, log: "build ok") }

      response "200", "deploy" do
        let(:app_id) { app_record.id }
        let(:id) { deploy.id }
        schema deploy_ref
        run_test! { |response| expect(JSON.parse(response.body)["log"]).to eq("build ok") }
      end

      response "401", "missing or invalid token" do
        let(:app_id) { app_record.id }
        let(:id) { deploy.id }
        let(:Authorization) { nil }
        schema error
        run_test!
      end

      response "404", "unknown deploy, or an app of a team the caller does not belong to" do
        let(:app_id) { foreign_app.id }
        let(:id) { deploy.id }
        schema error
        run_test!
      end
    end
  end

  path "/api/v1/apps/{app_id}/deploys/uploads" do
    parameter app_param

    post "Get a presigned URL to upload a source tarball (15 minutes)" do
      operationId "deploys.upload_url"
      tags "deploys"
      security [ { bearer: [] } ]
      produces "application/json"

      let(:app_id) { app_record.id }

      response "201", "upload slot" do
        before do
          allow(store).to receive(:configured?).and_return(true)
          allow(store).to receive(:presigned_put).and_return("https://signed.example/put-url")
        end
        schema type: :object, required: %w[archive_key upload_url expires_in],
               properties: { archive_key: { type: :string }, upload_url: { type: :string }, expires_in: { type: :integer } }
        run_test! { |response| expect(JSON.parse(response.body)["archive_key"]).to start_with("deploy-archives/#{app_record.id}/") }
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

      response "501", "no object store configured (upload_not_configured)" do
        before { allow(store).to receive(:configured?).and_return(false) }
        schema error
        run_test!
      end
    end
  end
end

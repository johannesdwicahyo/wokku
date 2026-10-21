# frozen_string_literal: true

require "openapi_helper"

RSpec.describe "API v1 releases", type: :request do
  let(:user) { users(:one) }
  let(:Authorization) { "Bearer #{api_v1_token_for(user)}" }
  let(:app_record) { app_records(:one) }
  let(:foreign_app) { app_records(:two) }
  let(:viewer) { create(:user).tap { |u| create(:team_membership, user: u, team: app_record.team, role: :viewer) } }
  let(:release) { app_record.releases.create!(description: "v1") }
  error = { "$ref" => "#/components/schemas/Error" }
  release_ref = { "$ref" => "#/components/schemas/Release" }
  app_param = { name: :app_id, in: :path, schema: { type: :string }, description: "App UUID or name" }
  id_param = { name: :id, in: :path, schema: { type: :string, format: :uuid } }

  path "/api/v1/apps/{app_id}/releases" do
    parameter app_param

    get "List releases, newest version first" do
      operationId "releases.list"
      tags "releases"
      security [ { bearer: [] } ]
      produces "application/json"

      response "200", "releases" do
        let(:app_id) { release.app_record_id }
        schema type: :array, items: release_ref
        run_test! { |response| expect(JSON.parse(response.body).map { |r| r["id"] }).to include(release.id) }
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

  path "/api/v1/apps/{app_id}/releases/{id}" do
    parameter app_param
    parameter id_param

    get "Show a release" do
      operationId "releases.show"
      tags "releases"
      security [ { bearer: [] } ]
      produces "application/json"

      response "200", "release" do
        let(:app_id) { app_record.id }
        let(:id) { release.id }
        schema release_ref
        run_test! { |response| expect(JSON.parse(response.body)["description"]).to eq("v1") }
      end

      response "401", "missing or invalid token" do
        let(:app_id) { app_record.id }
        let(:id) { release.id }
        let(:Authorization) { nil }
        schema error
        run_test!
      end

      response "404", "unknown release, or an app of a team the caller does not belong to" do
        let(:app_id) { foreign_app.id }
        let(:id) { release.id }
        schema error
        run_test!
      end
    end
  end

  path "/api/v1/apps/{app_id}/releases/{id}/rollback" do
    parameter app_param
    parameter id_param

    post "Roll back: redeploy a release's recorded artifact as a new release" do
      operationId "releases.rollback"
      tags "releases"
      security [ { bearer: [] } ]
      produces "application/json"

      let(:app_id) { app_record.id }
      let(:id) { release.id }

      response "201", "rollback deploy queued; the new release" do
        let(:archive_key) { "deploy-archives/#{app_record.id}/#{SecureRandom.uuid}.tar.gz" }
        before do
          app_record.deploys.create!(release: release, status: :succeeded, archive_key: archive_key)
          allow(Wokku.config.backup_store).to receive(:exists?).with(archive_key).and_return(true)
        end
        schema release_ref
        run_test! { |response| expect(JSON.parse(response.body)["description"]).to eq("Rollback to v#{release.version}") }
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

      response "404", "unknown release, or an app of a team the caller does not belong to" do
        let(:app_id) { foreign_app.id }
        schema error
        run_test!
      end

      response "422", "no artifact left to roll back to (rollback_artifact_missing)" do
        schema error
        run_test!
      end
    end
  end
end

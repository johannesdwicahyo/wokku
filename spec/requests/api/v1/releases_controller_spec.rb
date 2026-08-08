# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API::V1::ReleasesController (deep)", type: :request do
  let(:user) { users(:one) }
  let(:app_record) { app_records(:one) }
  let(:plain_token) { api_v1_token_for(user) }
  let(:headers) { { "Authorization" => "Bearer #{plain_token}" } }

  it "index returns releases ordered by version desc" do
    app_record.releases.create!(description: "v1")
    app_record.releases.create!(description: "v2")
    get "/api/v1/apps/#{app_record.id}/releases", headers: headers
    expect(response).to have_http_status(:success)
    versions = JSON.parse(response.body).map { |r| r["version"] }
    expect(versions.sort.reverse).to eq(versions)
  end

  it "show returns a specific release" do
    rel = app_record.releases.create!(description: "v1")
    get "/api/v1/apps/#{app_record.id}/releases/#{rel.id}", headers: headers
    expect(response).to have_http_status(:success)
    expect(JSON.parse(response.body)["description"]).to eq("v1")
  end

  describe "POST rollback — real rollback (Track A Phase 4a Task 4)" do
    it "rejects with a typed 422 when the release has no deploy recorded at all" do
      rel = app_record.releases.create!(description: "no-deploy-release")
      post "/api/v1/apps/#{app_record.id}/releases/#{rel.id}/rollback", headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body["error_code"]).to eq("rollback_artifact_missing")
      expect(body["hint"]).to include("no recorded deploy")
      expect(body["retryable"]).to eq(false)
    end

    it "rejects with a typed 422 for a legacy release whose deploy recorded neither artifact — no silent ps:rebuild placebo" do
      rel = app_record.releases.create!(description: "legacy-sha-only")
      app_record.deploys.create!(release: rel, status: :succeeded, commit_sha: "deadbeef1234567")

      expect {
        post "/api/v1/apps/#{app_record.id}/releases/#{rel.id}/rollback", headers: headers
      }.not_to change { app_record.deploys.count }
      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body["error_code"]).to eq("rollback_artifact_missing")
      expect(body["hint"]).to include("legacy deploy")
    end

    it "resolves from_image when image_ref is present and its tag is still on the host, and enqueues RollbackDeployJob" do
      rel = app_record.releases.create!(description: "historical")
      tag = "#{Hosts::Registry::HOST}/wokku-rollback/#{app_record.name}:11111111-1111-1111-1111-111111111111"
      app_record.deploys.create!(release: rel, status: :succeeded, image_ref: tag)
      allow_any_instance_of(Hosts::Registry).to receive(:tags)
        .with("wokku-rollback/#{app_record.name}")
        .and_return([ "11111111-1111-1111-1111-111111111111" ])

      expect {
        expect {
          expect {
            post "/api/v1/apps/#{app_record.id}/releases/#{rel.id}/rollback", headers: headers
          }.to have_enqueued_job(RollbackDeployJob)
        }.to change { app_record.releases.count }.by(1)
      }.to change { app_record.deploys.count }.by(1)
      expect(response).to have_http_status(:created)

      new_deploy = app_record.deploys.order(:created_at).last
      expect(new_deploy.image_ref).to eq(tag)
      expect(new_deploy.archive_key).to be_nil
    end

    it "falls back to from_archive when the image tag was pruned from the host but the archive still exists" do
      rel = app_record.releases.create!(description: "historical")
      tag = "#{Hosts::Registry::HOST}/wokku-rollback/#{app_record.name}:22222222-2222-2222-2222-222222222222"
      archive_key = "deploy-archives/#{app_record.id}/#{SecureRandom.uuid}.tar.gz"
      app_record.deploys.create!(release: rel, status: :succeeded, image_ref: tag, archive_key: archive_key)
      allow_any_instance_of(Hosts::Registry).to receive(:tags).with("wokku-rollback/#{app_record.name}").and_return([])
      allow(Wokku.config.backup_store).to receive(:exists?).with(archive_key).and_return(true)

      post "/api/v1/apps/#{app_record.id}/releases/#{rel.id}/rollback", headers: headers
      expect(response).to have_http_status(:created)

      new_deploy = app_record.deploys.order(:created_at).last
      expect(new_deploy.archive_key).to eq(archive_key)
      expect(new_deploy.image_ref).to be_nil
    end

    it "returns a typed 422 when the image tag was pruned and the archive is also gone" do
      rel = app_record.releases.create!(description: "historical")
      tag = "#{Hosts::Registry::HOST}/wokku-rollback/#{app_record.name}:33333333-3333-3333-3333-333333333333"
      archive_key = "deploy-archives/#{app_record.id}/#{SecureRandom.uuid}.tar.gz"
      app_record.deploys.create!(release: rel, status: :succeeded, image_ref: tag, archive_key: archive_key)
      allow_any_instance_of(Hosts::Registry).to receive(:tags).with("wokku-rollback/#{app_record.name}").and_return([])
      allow(Wokku.config.backup_store).to receive(:exists?).with(archive_key).and_return(false)

      expect {
        post "/api/v1/apps/#{app_record.id}/releases/#{rel.id}/rollback", headers: headers
      }.not_to change { app_record.deploys.count }
      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body["error_code"]).to eq("rollback_artifact_missing")
      expect(body["hint"]).to include("rollback image tag was pruned")
      expect(body["hint"]).to include("archive is no longer in storage")
    end

    it "resolves from_archive directly when only archive_key was ever recorded (no image_ref)" do
      rel = app_record.releases.create!(description: "tarball-only")
      archive_key = "deploy-archives/#{app_record.id}/#{SecureRandom.uuid}.tar.gz"
      app_record.deploys.create!(release: rel, status: :succeeded, archive_key: archive_key)
      allow(Wokku.config.backup_store).to receive(:exists?).with(archive_key).and_return(true)

      post "/api/v1/apps/#{app_record.id}/releases/#{rel.id}/rollback", headers: headers
      expect(response).to have_http_status(:created)
    end
  end
end

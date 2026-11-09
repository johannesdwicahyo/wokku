# frozen_string_literal: true

require "rails_helper"

RSpec.describe "POST /api/v1/apps/:app_id/deploys", type: :request do
  let(:user) { users(:one) }
  let(:app_record) { app_records(:one) }
  let(:token) { api_v1_token_for(user) }
  let(:headers) { { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" } }
  let(:store) { instance_double(Wokku::Providers::LocalBackupStore) }
  let(:archive_key) { "deploy-archives/#{app_record.id}/#{SecureRandom.uuid}.tar.gz" }

  before do
    allow(Wokku.config).to receive(:backup_store).and_return(store)
    allow(::Apps::Lifecycle::DeployLock).to receive(:new)
      .and_return(instance_double(::Apps::Lifecycle::DeployLock, locked?: false))
  end

  it "returns 401 without a token" do
    post "/api/v1/apps/#{app_record.id}/deploys", params: { archive_key: archive_key }, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it "returns 404 for a non-team member" do
    other_user = users(:two)
    other_token = api_v1_token_for(other_user)
    post "/api/v1/apps/#{app_record.id}/deploys",
         params: { archive_key: archive_key },
         headers: { "Authorization" => "Bearer #{other_token}" },
         as: :json
    expect(response).to have_http_status(:not_found)
  end

  context "when the app is locked" do
    it "returns 409 app_locked" do
      allow(::Apps::Lifecycle::DeployLock).to receive(:new)
        .and_return(instance_double(::Apps::Lifecycle::DeployLock, locked?: true))
      post "/api/v1/apps/#{app_record.id}/deploys", params: { archive_key: archive_key }, headers: headers, as: :json
      expect(response).to have_http_status(:conflict)
      body = JSON.parse(response.body)
      expect(body["error_code"]).to eq("app_locked")
    end
  end

  context "with an archive_key that doesn't match this app's prefix" do
    it "returns 400 invalid_params for another app's key" do
      other_app = app_records(:two)
      foreign_key = "deploy-archives/#{other_app.id}/#{SecureRandom.uuid}.tar.gz"
      post "/api/v1/apps/#{app_record.id}/deploys", params: { archive_key: foreign_key }, headers: headers, as: :json
      expect(response).to have_http_status(:bad_request)
      body = JSON.parse(response.body)
      expect(body["error_code"]).to eq("invalid_params")
    end

    it "returns 400 invalid_params for a malformed key" do
      post "/api/v1/apps/#{app_record.id}/deploys", params: { archive_key: "not-a-real-key" }, headers: headers, as: :json
      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)["error_code"]).to eq("invalid_params")
    end

    it "returns 400 invalid_params when archive_key is missing" do
      post "/api/v1/apps/#{app_record.id}/deploys", headers: headers
      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)["error_code"]).to eq("invalid_params")
    end
  end

  context "when the archive does not exist in the store" do
    before { allow(store).to receive(:exists?).and_return(false) }

    it "returns 422 archive_missing" do
      post "/api/v1/apps/#{app_record.id}/deploys", params: { archive_key: archive_key }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body["error_code"]).to eq("archive_missing")
      expect(body["retryable"]).to be(false)
      expect(body["hint"]).to match(/upload/i)
    end
  end

  context "when the archive exists in the store" do
    before { allow(store).to receive(:exists?).and_return(true) }

    it "creates a Release + Deploy with the archive_key, enqueues TarballDeployJob, and returns 202" do
      expect {
        post "/api/v1/apps/#{app_record.id}/deploys", params: { archive_key: archive_key }, headers: headers, as: :json
      }.to have_enqueued_job(TarballDeployJob)

      expect(response).to have_http_status(:accepted)
      body = JSON.parse(response.body)
      expect(body["status"]).to eq("pending")

      deploy = Deploy.find(body["deploy_id"])
      expect(deploy.archive_key).to eq(archive_key)
      expect(deploy.status).to eq("pending")
      expect(deploy.release).to be_present
    end

    it "checks the store with the given archive_key" do
      post "/api/v1/apps/#{app_record.id}/deploys", params: { archive_key: archive_key }, headers: headers, as: :json
      expect(store).to have_received(:exists?).with(archive_key)
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe "POST /api/v1/apps/:app_id/deploys/uploads", type: :request do
  let(:user) { users(:one) }
  let(:app_record) { app_records(:one) }
  let(:token) { api_v1_token_for(user) }
  let(:headers) { { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" } }
  let(:store) { instance_double(Wokku::Providers::LocalBackupStore) }

  before do
    allow(Wokku.config).to receive(:backup_store).and_return(store)
  end

  it "returns 401 without a token" do
    post "/api/v1/apps/#{app_record.id}/deploys/uploads"
    expect(response).to have_http_status(:unauthorized)
  end

  it "returns 403 for a non-team member" do
    other_user = users(:two)
    other_token = api_v1_token_for(other_user)
    post "/api/v1/apps/#{app_record.id}/deploys/uploads",
         headers: { "Authorization" => "Bearer #{other_token}" }
    expect(response).to have_http_status(:forbidden)
  end

  context "when the store is configured" do
    before do
      allow(store).to receive(:configured?).and_return(true)
      allow(store).to receive(:presigned_put).and_return("https://signed.example/put-url")
    end

    it "returns a presigned PUT URL scoped to a deploy-archives/<app_id>/<uuid>.tar.gz key" do
      post "/api/v1/apps/#{app_record.id}/deploys/uploads", headers: headers
      expect(response).to have_http_status(:created)

      body = JSON.parse(response.body)
      expect(body["archive_key"]).to match(%r{\Adeploy-archives/#{app_record.id}/[0-9a-f-]{36}\.tar\.gz\z})
      expect(body["upload_url"]).to eq("https://signed.example/put-url")
      expect(body["expires_in"]).to eq(900)

      expect(store).to have_received(:presigned_put).with(body["archive_key"], expires_in: 15.minutes)
    end
  end

  context "when the store cannot presign (LocalBackupStore, OSS default)" do
    before do
      allow(store).to receive(:configured?).and_return(true)
      allow(store).to receive(:presigned_put).and_return(nil)
    end

    it "returns 501 upload_not_configured instead of a null URL" do
      post "/api/v1/apps/#{app_record.id}/deploys/uploads", headers: headers
      expect(response).to have_http_status(:not_implemented)
      expect(JSON.parse(response.body)["error_code"]).to eq("upload_not_configured")
    end
  end

  context "when the store is not configured" do
    before { allow(store).to receive(:configured?).and_return(false) }

    it "returns 501 upload_not_configured" do
      post "/api/v1/apps/#{app_record.id}/deploys/uploads", headers: headers
      expect(response).to have_http_status(:not_implemented)

      body = JSON.parse(response.body)
      expect(body["error_code"]).to eq("upload_not_configured")
      expect(body["error"]).to match(/not configured/i)
      expect(body["hint"]).to match(/WOKKU_BACKUP_S3/)
      expect(body["retryable"]).to be(false)
    end
  end
end

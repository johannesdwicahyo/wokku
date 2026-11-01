# frozen_string_literal: true

require "rails_helper"

# Dashboard actions brought to the API (channel parity phase 2, 2026-11-01).
RSpec.describe "API parity: preview settings, vitals token, GitHub repos", type: :request do
  let(:user) { users(:one) }
  let(:app_record) { app_records(:one) }
  let(:headers) { { "Authorization" => "Bearer #{api_v1_token_for(user)}" } }

  describe "PATCH /api/v1/apps/:id/preview_settings" do
    it "turns previews on with a database strategy" do
      patch "/api/v1/apps/#{app_record.id}/preview_settings", params: { preview_enabled: true, database_strategy: "snapshot" }, headers: headers
      expect(response).to have_http_status(:ok)
      expect(app_record.reload).to have_attributes(preview_enabled: true, database_strategy: "snapshot")
    end

    it "rejects an unknown database strategy" do
      patch "/api/v1/apps/#{app_record.id}/preview_settings", params: { database_strategy: "copy" }, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(app_record.reload.database_strategy).to eq("empty")
    end

    it "404s for another team's app" do
      patch "/api/v1/apps/#{app_records(:two).id}/preview_settings", params: { preview_enabled: true }, headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/apps/:id/vitals/rotate_token" do
    it "returns a new token and stores it" do
      old = app_record.vitals_ingest_token
      post "/api/v1/apps/#{app_record.id}/vitals/rotate_token", headers: headers
      token = JSON.parse(response.body)["vitals_ingest_token"]
      expect(token).to be_present
      expect(token).not_to eq(old)
      expect(app_record.reload.vitals_ingest_token).to eq(token)
    end
  end

  describe "GET /api/v1/github/repos" do
    it "explains how to install the GitHub App when it isn't installed" do
      user.update_columns(github_installation_id: nil)
      get "/api/v1/github/repos", headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error_code"]).to eq("github_not_installed")
    end

    context "with the app installed" do
      let(:github) { instance_double(GithubApp) }

      before do
        user.update_columns(github_installation_id: 42)
        allow(GithubApp).to receive(:new).with(42).and_return(github)
      end

      it "lists repos" do
        repo = double(full_name: "acme/shop", private: true, default_branch: "main")
        allow(github).to receive(:repos).and_return(double(repositories: [ repo ]))
        get "/api/v1/github/repos", headers: headers
        expect(JSON.parse(response.body)).to eq([ { "full_name" => "acme/shop", "private" => true, "default_branch" => "main" } ])
      end

      it "lists a repo's branches" do
        allow(github).to receive(:branches).with("acme/shop").and_return(%w[main staging])
        get "/api/v1/github/repos", params: { repo: "acme/shop" }, headers: headers
        expect(JSON.parse(response.body)).to eq("repo" => "acme/shop", "branches" => %w[main staging])
      end

      it "answers 502 github_failed when GitHub errors" do
        allow(github).to receive(:repos).and_raise(Octokit::BadGateway)
        get "/api/v1/github/repos", headers: headers
        expect(response).to have_http_status(:bad_gateway)
        expect(JSON.parse(response.body)["error_code"]).to eq("github_failed")
      end
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API::V1::AppsController (deep)", type: :request do
  let(:user) { users(:one) }
  let(:app_record) { app_records(:one) }
  let(:plain_token) { api_v1_token_for(user) }
  let(:headers) { { "Authorization" => "Bearer #{plain_token}" } }

  it "deploy enqueues DeployJob and returns 202" do
    # The deploy endpoint checks the deploy lock via Dokku SSH inline before
    # enqueuing — stub it so the request doesn't make a real SSH connection.
    allow_any_instance_of(Apps::Lifecycle::DeployLock).to receive(:locked?).and_return(false)
    expect {
      expect {
        expect {
          post "/api/v1/apps/#{app_record.id}/deploy", headers: headers
        }.to have_enqueued_job(DeployJob)
      }.to change { app_record.reload.releases.count }.by(1)
    }.to change { app_record.reload.deploys.count }.by(1)
    expect(response).to have_http_status(:accepted)
    body = JSON.parse(response.body)
    expect(body["deploy_id"]).to be_present
    expect(body["release_id"]).to be_present
  end

  it "github_connect requires repo parameter" do
    post "/api/v1/apps/#{app_record.id}/github_connect", headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
  end

  context "when the repo is in the caller's installation" do
    before { allow(GithubApp).to receive(:repo_owned_by_installation?).and_return(true) }

    it "github_connect stores repo + generates webhook secret" do
      expect(app_record.github_repo_full_name).to be_nil
      post "/api/v1/apps/#{app_record.id}/github_connect",
        params: { repo: "owner/repo", branch: "develop" },
        headers: headers
      expect(response).to have_http_status(:success)
      app_record.reload
      expect(app_record.github_repo_full_name).to eq("owner/repo")
      expect(app_record.deploy_branch).to eq("develop")
      expect(app_record.git_repository_url).to eq("https://github.com/owner/repo.git")
      expect(app_record.github_webhook_secret).to be_present
    end

    it "github_connect preserves existing webhook secret across reconnects" do
      app_record.update!(github_webhook_secret: "preserve-me")
      post "/api/v1/apps/#{app_record.id}/github_connect",
        params: { repo: "owner/repo" },
        headers: headers
      expect(app_record.reload.github_webhook_secret).to eq("preserve-me")
    end
  end

  it "github_connect refuses a repo outside the caller's installation" do
    allow(GithubApp).to receive(:repo_owned_by_installation?).and_return(false)
    post "/api/v1/apps/#{app_record.id}/github_connect", params: { repo: "victim/private" }, headers: headers
    expect(response).to have_http_status(:forbidden)
    expect(JSON.parse(response.body)["error_code"]).to eq("github_repo_not_owned")
    expect(app_record.reload.github_repo_full_name).to be_nil
  end

  it "github_disconnect clears repo info" do
    app_record.update!(github_repo_full_name: "owner/repo", github_webhook_secret: "s")
    delete "/api/v1/apps/#{app_record.id}/github_disconnect", headers: headers
    expect(response).to have_http_status(:success)
    expect(app_record.reload.github_repo_full_name).to be_nil
    expect(app_record.github_webhook_secret).to be_nil
  end
end

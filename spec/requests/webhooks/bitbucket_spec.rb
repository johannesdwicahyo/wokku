# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Webhooks::BitbucketController", type: :request do
  BITBUCKET_SECRET = "test_bitbucket_webhook_secret"

  before do
    @original_secret = ENV["BITBUCKET_WEBHOOK_SECRET"]
    ENV["BITBUCKET_WEBHOOK_SECRET"] = BITBUCKET_SECRET
  end

  after do
    ENV["BITBUCKET_WEBHOOK_SECRET"] = @original_secret
  end

  def signed_post(payload, event: "repo:push")
    sig = "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", BITBUCKET_SECRET, payload)
    post "/webhooks/bitbucket",
         params: payload,
         headers: {
           "Content-Type" => "application/json",
           "X-Event-Key" => event,
           "X-Hub-Signature" => sig
         }
  end

  # ---------------------------------------------------------------------------
  # Signature verification
  # ---------------------------------------------------------------------------

  it "rejects request with missing signature" do
    post "/webhooks/bitbucket",
         params: '{"repository":{}}',
         headers: {
           "Content-Type" => "application/json",
           "X-Event-Key" => "repo:push"
         }
    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects request with wrong signature" do
    post "/webhooks/bitbucket",
         params: '{"repository":{}}',
         headers: {
           "Content-Type" => "application/json",
           "X-Event-Key" => "repo:push",
           "X-Hub-Signature" => "sha256=invalidsignature"
         }
    expect(response).to have_http_status(:unauthorized)
  end

  it "accepts valid signature and returns ok for unknown event" do
    signed_post('{"repository":{}}', event: "issue:created")
    expect(response).to have_http_status(:ok)
  end

  # ---------------------------------------------------------------------------
  # Push events (repo:push)
  # ---------------------------------------------------------------------------

  context "repo:push event" do
    let!(:bb_app) do
      create(:app_record,
             git_provider: "bitbucket",
             git_repo_full_name: "owner/bb-repo",
             deploy_branch: "main")
    end

    it "enqueues BitbucketDeployJob for matching app" do
      payload = {
        repository: { full_name: "owner/bb-repo" },
        push: {
          changes: [
            {
              new: {
                name: "main",
                target: { hash: "abc123def456", message: "Fix bug" }
              }
            }
          ]
        }
      }.to_json

      expect {
        signed_post(payload, event: "repo:push")
      }.to have_enqueued_job(BitbucketDeployJob)
      expect(response).to have_http_status(:ok)
    end

    it "creates Deploy and Release records" do
      payload = {
        repository: { full_name: "owner/bb-repo" },
        push: {
          changes: [
            {
              new: {
                name: "main",
                target: { hash: "deadbeef1234", message: "feat: initial" }
              }
            }
          ]
        }
      }.to_json

      expect {
        signed_post(payload, event: "repo:push")
      }.to change(Deploy, :count).by(1).and change(Release, :count).by(1)
    end

    it "does not trigger for non-matching branch" do
      payload = {
        repository: { full_name: "owner/bb-repo" },
        push: {
          changes: [
            {
              new: {
                name: "feature-branch",
                target: { hash: "abc123", message: "WIP" }
              }
            }
          ]
        }
      }.to_json

      expect {
        signed_post(payload, event: "repo:push")
      }.not_to have_enqueued_job(BitbucketDeployJob)
      expect(response).to have_http_status(:ok)
    end
  end

  # ---------------------------------------------------------------------------
  # Pull Request events — routed through Preview::EventDispatcher
  # ---------------------------------------------------------------------------

  context "pullrequest events" do
    let!(:parent) do
      create(:app_record,
             git_provider: "bitbucket",
             git_repo_full_name: "octo/repo",
             preview_enabled: true)
    end

    let(:pr_payload) do
      File.read(Rails.root.join("spec/fixtures/webhooks/bitbucket/pullrequest_created.json"))
    end

    it "enqueues Preview::DeployJob for pullrequest:created" do
      expect {
        signed_post(pr_payload, event: "pullrequest:created")
      }.to have_enqueued_job(Preview::DeployJob)
      expect(response).to have_http_status(:ok)
    end

    it "enqueues Preview::DeployJob for pullrequest:updated" do
      payload = File.read(Rails.root.join("spec/fixtures/webhooks/bitbucket/pullrequest_updated.json"))
      expect {
        signed_post(payload, event: "pullrequest:updated")
      }.to have_enqueued_job(Preview::DeployJob)
      expect(response).to have_http_status(:ok)
    end

    it "enqueues Preview::CleanupJob for pullrequest:fulfilled (merged)" do
      create(:app_record, :preview, parent_app: parent, pr_number: 7, server: parent.server)
      payload = File.read(Rails.root.join("spec/fixtures/webhooks/bitbucket/pullrequest_fulfilled.json"))
      expect {
        signed_post(payload, event: "pullrequest:fulfilled")
      }.to have_enqueued_job(Preview::CleanupJob)
      expect(response).to have_http_status(:ok)
    end

    it "enqueues Preview::CleanupJob for pullrequest:rejected (closed)" do
      create(:app_record, :preview, parent_app: parent, pr_number: 7, server: parent.server)
      payload = File.read(Rails.root.join("spec/fixtures/webhooks/bitbucket/pullrequest_rejected.json"))
      expect {
        signed_post(payload, event: "pullrequest:rejected")
      }.to have_enqueued_job(Preview::CleanupJob)
      expect(response).to have_http_status(:ok)
    end

    it "returns ok with no enqueue when no matching parent app" do
      parent.update!(git_repo_full_name: "other/repo")
      expect {
        signed_post(pr_payload, event: "pullrequest:created")
      }.not_to have_enqueued_job(Preview::DeployJob)
      expect(response).to have_http_status(:ok)
    end
  end
end

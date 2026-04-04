require "test_helper"

class Webhooks::BitbucketControllerTest < ActionDispatch::IntegrationTest
  BITBUCKET_SECRET = "test_bitbucket_webhook_secret"

  setup do
    @original_secret = ENV["BITBUCKET_WEBHOOK_SECRET"]
    ENV["BITBUCKET_WEBHOOK_SECRET"] = BITBUCKET_SECRET
  end

  teardown do
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

  test "rejects request with missing signature" do
    post "/webhooks/bitbucket",
      params: '{"repository":{}}',
      headers: {
        "Content-Type" => "application/json",
        "X-Event-Key" => "repo:push"
      }
    assert_response :unauthorized
  end

  test "rejects request with wrong signature" do
    payload = '{"repository":{}}'
    post "/webhooks/bitbucket",
      params: payload,
      headers: {
        "Content-Type" => "application/json",
        "X-Event-Key" => "repo:push",
        "X-Hub-Signature" => "sha256=invalidsignature"
      }
    assert_response :unauthorized
  end

  test "accepts valid signature and returns ok for unknown event" do
    signed_post('{"repository":{}}', event: "issue:created")
    assert_response :ok
  end

  test "push event enqueues BitbucketDeployJob for matching app" do
    app = app_records(:one)
    app.update!(git_provider: "bitbucket", git_repo_full_name: "owner/bb-repo", deploy_branch: "main")

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

    assert_enqueued_jobs 1, only: BitbucketDeployJob do
      signed_post(payload, event: "repo:push")
    end
    assert_response :ok
  ensure
    app.update!(git_provider: nil, git_repo_full_name: nil)
  end

  test "push event creates deploy and release records" do
    app = app_records(:one)
    app.update!(git_provider: "bitbucket", git_repo_full_name: "owner/bb-push-test", deploy_branch: "main")

    payload = {
      repository: { full_name: "owner/bb-push-test" },
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

    assert_difference "Deploy.count", 1 do
      assert_difference "Release.count", 1 do
        signed_post(payload, event: "repo:push")
      end
    end
  ensure
    app.update!(git_provider: nil, git_repo_full_name: nil)
  end

  test "push event does not trigger for non-matching branch" do
    app = app_records(:one)
    app.update!(git_provider: "bitbucket", git_repo_full_name: "owner/bb-branch-test", deploy_branch: "main")

    payload = {
      repository: { full_name: "owner/bb-branch-test" },
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

    assert_no_enqueued_jobs only: BitbucketDeployJob do
      signed_post(payload, event: "repo:push")
    end
    assert_response :ok
  ensure
    app.update!(git_provider: nil, git_repo_full_name: nil)
  end

  test "pullrequest:created enqueues PrPreviewDeployJob" do
    app = app_records(:one)
    app.update!(git_provider: "bitbucket", git_repo_full_name: "owner/bb-pr-repo")

    payload = {
      repository: { full_name: "owner/bb-pr-repo" },
      pullrequest: {
        id: 7,
        title: "New Feature",
        source: {
          branch: { name: "feature-branch" },
          commit: { hash: "abc123" }
        }
      }
    }.to_json

    assert_enqueued_jobs 1, only: PrPreviewDeployJob do
      signed_post(payload, event: "pullrequest:created")
    end
    assert_response :ok
  ensure
    app.update!(git_provider: nil, git_repo_full_name: nil)
  end

  test "pullrequest:updated enqueues PrPreviewDeployJob" do
    app = app_records(:one)
    app.update!(git_provider: "bitbucket", git_repo_full_name: "owner/bb-pr-update")

    payload = {
      repository: { full_name: "owner/bb-pr-update" },
      pullrequest: {
        id: 9,
        title: "Updated PR",
        source: {
          branch: { name: "fix-branch" },
          commit: { hash: "sha999" }
        }
      }
    }.to_json

    assert_enqueued_jobs 1, only: PrPreviewDeployJob do
      signed_post(payload, event: "pullrequest:updated")
    end
    assert_response :ok
  ensure
    app.update!(git_provider: nil, git_repo_full_name: nil)
  end

  test "pullrequest:fulfilled enqueues PrPreviewCleanupJob" do
    app = app_records(:one)
    app.update!(git_provider: "bitbucket", git_repo_full_name: "owner/bb-pr-fulfill")

    payload = {
      repository: { full_name: "owner/bb-pr-fulfill" },
      pullrequest: {
        id: 11,
        title: "Merged PR",
        source: {
          branch: { name: "merge-branch" },
          commit: { hash: "sha000" }
        }
      }
    }.to_json

    assert_enqueued_jobs 1, only: PrPreviewCleanupJob do
      signed_post(payload, event: "pullrequest:fulfilled")
    end
    assert_response :ok
  ensure
    app.update!(git_provider: nil, git_repo_full_name: nil)
  end

  test "pullrequest:created returns ok when no matching apps" do
    payload = {
      repository: { full_name: "nobody/nonexistent" },
      pullrequest: {
        id: 1,
        title: "Orphan",
        source: {
          branch: { name: "orphan-branch" },
          commit: { hash: "sha" }
        }
      }
    }.to_json

    assert_no_enqueued_jobs only: PrPreviewDeployJob do
      signed_post(payload, event: "pullrequest:created")
    end
    assert_response :ok
  end
end

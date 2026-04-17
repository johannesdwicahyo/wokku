require "test_helper"

class Api::V1::AppsControllerDeepTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @app = app_records(:one)
    _, @plain_token = ApiToken.create_with_token!(user: @user, name: "test")
  end

  def auth_headers
    { "Authorization" => "Bearer #{@plain_token}" }
  end

  test "deploy enqueues DeployJob and returns 202" do
    assert_difference "@app.deploys.count", 1 do
      assert_difference "@app.releases.count", 1 do
        assert_enqueued_with(job: DeployJob) do
          post "/api/v1/apps/#{@app.id}/deploy", headers: auth_headers
        end
      end
    end
    assert_response :accepted
    body = JSON.parse(response.body)
    assert body["deploy_id"].present?
    assert body["release_id"].present?
  end

  test "github_connect requires repo parameter" do
    post "/api/v1/apps/#{@app.id}/github_connect", headers: auth_headers
    assert_response :unprocessable_entity
  end

  test "github_connect stores repo + generates webhook secret" do
    assert_nil @app.github_repo_full_name
    post "/api/v1/apps/#{@app.id}/github_connect",
      params: { repo: "owner/repo", branch: "develop" },
      headers: auth_headers
    assert_response :success
    @app.reload
    assert_equal "owner/repo", @app.github_repo_full_name
    assert_equal "develop", @app.deploy_branch
    assert_equal "https://github.com/owner/repo.git", @app.git_repository_url
    assert @app.github_webhook_secret.present?
  end

  test "github_connect preserves existing webhook secret across reconnects" do
    @app.update!(github_webhook_secret: "preserve-me")
    post "/api/v1/apps/#{@app.id}/github_connect",
      params: { repo: "owner/repo" },
      headers: auth_headers
    assert_equal "preserve-me", @app.reload.github_webhook_secret
  end

  test "github_disconnect clears repo info" do
    @app.update!(github_repo_full_name: "owner/repo", github_webhook_secret: "s")
    delete "/api/v1/apps/#{@app.id}/github_disconnect", headers: auth_headers
    assert_response :success
    assert_nil @app.reload.github_repo_full_name
    assert_nil @app.github_webhook_secret
  end
end

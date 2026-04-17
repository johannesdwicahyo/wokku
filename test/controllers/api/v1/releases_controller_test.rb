require "test_helper"

class Api::V1::ReleasesControllerDeepTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @app = app_records(:one)
    _, @plain_token = ApiToken.create_with_token!(user: @user, name: "test")
  end

  def auth_headers
    { "Authorization" => "Bearer #{@plain_token}" }
  end

  test "index returns releases ordered by version desc" do
    @app.releases.create!(description: "v1")
    @app.releases.create!(description: "v2")
    get "/api/v1/apps/#{@app.id}/releases", headers: auth_headers
    assert_response :success
    versions = JSON.parse(response.body).map { |r| r["version"] }
    assert_equal versions.sort.reverse, versions
  end

  test "show returns a specific release" do
    rel = @app.releases.create!(description: "v1")
    get "/api/v1/apps/#{@app.id}/releases/#{rel.id}", headers: auth_headers
    assert_response :success
    assert_equal "v1", JSON.parse(response.body)["description"]
  end

  test "rollback refuses when target release has no commit sha" do
    rel = @app.releases.create!(description: "no-sha-release")
    post "/api/v1/apps/#{@app.id}/releases/#{rel.id}/rollback", headers: auth_headers
    assert_response :unprocessable_entity
  end

  test "rollback enqueues a new DeployJob when target has a commit sha" do
    rel = @app.releases.create!(description: "historical")
    @app.deploys.create!(release: rel, status: :succeeded, commit_sha: "deadbeef1234567")

    assert_enqueued_jobs 1, only: DeployJob do
      assert_difference "@app.releases.count", 1 do
        assert_difference "@app.deploys.count", 1 do
          post "/api/v1/apps/#{@app.id}/releases/#{rel.id}/rollback", headers: auth_headers
        end
      end
    end
    assert_response :created
  end
end

require "test_helper"

class Dashboard::GithubControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:two)  # admin
    @app = app_records(:two)
  end

  test "redirects to login when not authenticated on repos" do
    get "/dashboard/apps/#{@app.id}/github/repos"
    assert_response :redirect
  end

  test "repos redirects when no github installation_id" do
    sign_in @user
    @user.update!(github_installation_id: nil)
    get "/dashboard/apps/#{@app.id}/github/repos"
    # Redirects to external GitHub URL (open redirect is intentional for OAuth flows)
    assert_response :redirect
  end

  test "redirects to login when not authenticated on connect" do
    post "/dashboard/apps/#{@app.id}/github/connect", params: { repo: "owner/repo", branch: "main" }
    assert_response :redirect
  end

  test "connect updates app and redirects when authenticated" do
    sign_in @user
    post "/dashboard/apps/#{@app.id}/github/connect", params: { repo: "owner/repo", branch: "main" }
    assert_response :redirect
    @app.reload
    assert_equal "owner/repo", @app.github_repo_full_name
  end

  test "redirects to login when not authenticated on disconnect" do
    delete "/dashboard/apps/#{@app.id}/github/disconnect"
    assert_response :redirect
  end

  test "disconnect clears repo and redirects when authenticated" do
    sign_in @user
    @app.update!(github_repo_full_name: "owner/repo")
    delete "/dashboard/apps/#{@app.id}/github/disconnect"
    assert_response :redirect
    @app.reload
    assert_nil @app.github_repo_full_name
  end
end

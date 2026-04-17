require "test_helper"

class Github::CallbacksControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    sign_in @user
  end

  test "redirects to sign in when unauthenticated" do
    sign_out @user
    get github_callback_path, params: { installation_id: "12345" }
    assert_response :redirect
  end

  test "stores installation id when provided" do
    GithubApp.stubs(:configured?).returns(false)
    get github_callback_path, params: { installation_id: "99999" }
    assert_redirected_to dashboard_apps_path
    assert_equal 99999, @user.reload.github_installation_id.to_i
  end

  test "persists fetched github username when GithubApp is configured" do
    owner = OpenStruct.new(login: "octocat")
    repo = OpenStruct.new(owner: owner)
    repos = OpenStruct.new(repositories: [ repo ])
    GithubApp.stubs(:configured?).returns(true)
    GithubApp.any_instance.stubs(:repos).returns(repos)

    get github_callback_path, params: { installation_id: "42" }
    assert_equal "octocat", @user.reload.github_username
  end

  test "swallows GithubApp errors and still persists installation_id" do
    GithubApp.stubs(:configured?).returns(true)
    GithubApp.any_instance.stubs(:repos).raises(StandardError, "api down")

    get github_callback_path, params: { installation_id: "42" }
    assert_equal 42, @user.reload.github_installation_id.to_i
    assert_nil @user.github_username
  end

  test "shows alert when installation_id is missing" do
    get github_callback_path
    assert_redirected_to dashboard_apps_path
    assert_match(/failed/i, flash[:alert])
  end
end

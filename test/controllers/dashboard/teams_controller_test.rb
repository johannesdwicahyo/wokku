require "test_helper"

class Dashboard::TeamsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:two)  # role: admin (1)
    @team = teams(:two)
  end

  test "redirects to login when not authenticated on index" do
    get "/dashboard/teams"
    assert_response :redirect
  end

  test "shows teams index when authenticated" do
    sign_in @user
    get "/dashboard/teams"
    assert_response :success
  end

  test "redirects to login when not authenticated on show" do
    get "/dashboard/teams/#{@team.id}"
    assert_response :redirect
  end

  test "shows team when authenticated" do
    sign_in @user
    get "/dashboard/teams/#{@team.id}"
    assert_response :success
  end

  test "redirects to login when not authenticated on new" do
    get "/dashboard/teams/new"
    assert_response :redirect
  end

  test "shows new team form when authenticated" do
    sign_in @user
    get "/dashboard/teams/new"
    assert_response :success
  end

  test "redirects to login when not authenticated on create" do
    post "/dashboard/teams", params: { team: { name: "New Team" } }
    assert_response :redirect
  end

  test "creates team when authenticated" do
    sign_in @user
    assert_difference("Team.count", 1) do
      post "/dashboard/teams", params: { team: { name: "Brand New Team" } }
    end
    assert_response :redirect
    assert_redirected_to "/dashboard/teams"
  end
end

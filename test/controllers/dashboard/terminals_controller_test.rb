require "test_helper"

class Dashboard::TerminalsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:two)  # admin (system role 1)
    @app = app_records(:two)
    @server = servers(:two)
  end

  test "redirects to login when not authenticated on app terminal" do
    get "/dashboard/apps/#{@app.id}/terminal"
    assert_response :redirect
  end

  test "shows app terminal when authenticated as admin" do
    sign_in @user
    get "/dashboard/apps/#{@app.id}/terminal"
    assert_response :success
  end

  test "redirects to login when not authenticated on server terminal" do
    get "/dashboard/servers/#{@server.id}/terminal"
    assert_response :redirect
  end

  test "shows server terminal when authenticated as admin" do
    sign_in @user
    get "/dashboard/servers/#{@server.id}/terminal"
    assert_response :success
  end

  test "redirects non-team-admin away from server terminal" do
    # Create a user who is a team member but not an admin of the target team.
    member_user = User.create!(email: "member@example.com", password: "password123", name: "Member", role: :member)
    TeamMembership.create!(user: member_user, team: teams(:two), role: :member)
    sign_in member_user
    get "/dashboard/servers/#{@server.id}/terminal"
    assert_response :redirect
  end
end

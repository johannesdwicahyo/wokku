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

  test "redirects non-admin away from server terminal" do
    # users(:one) has system role 0 (not admin), is in team :one with server :one
    non_admin = users(:one)
    sign_in non_admin
    server_one = servers(:one)
    get "/dashboard/servers/#{server_one.id}/terminal"
    assert_response :redirect
  end
end

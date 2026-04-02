require "test_helper"

class Dashboard::ServersControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:two)  # role: admin (1)
  end

  test "redirects to login when not authenticated" do
    get "/dashboard/servers"
    assert_response :redirect
  end

  test "shows servers index when authenticated" do
    sign_in @user
    get "/dashboard/servers"
    assert_response :success
  end
end

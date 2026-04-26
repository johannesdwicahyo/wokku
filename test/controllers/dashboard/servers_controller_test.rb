require "test_helper"

class Dashboard::ServersControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "redirects to login when not authenticated" do
    get "/dashboard/servers"
    assert_response :redirect
  end

  test "shows servers index to non-admin users (read-only)" do
    sign_in users(:one)
    get "/dashboard/servers"
    assert_response :success
  end

  test "shows servers index to platform admins" do
    sign_in users(:admin)  # role: 1, otp_required_for_login: true
    get "/dashboard/servers"
    assert_response :success
  end
end

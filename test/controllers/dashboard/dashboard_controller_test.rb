require "test_helper"

class Dashboard::DashboardControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:two)   # role: admin (1)
  end

  # ---------------------------------------------------------------------------
  # show (GET /dashboard/)
  # ---------------------------------------------------------------------------

  test "show: redirects when not authenticated" do
    get "/dashboard/"
    assert_response :redirect
  end

  test "show: returns 200 when authenticated" do
    sign_in @user
    get "/dashboard/"
    assert_response :success
  end

  test "show: member (role 0) can access dashboard" do
    sign_in users(:one)
    get "/dashboard/"
    assert_response :success
  end
end

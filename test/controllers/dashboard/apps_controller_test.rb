require "test_helper"

class Dashboard::AppsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:two)  # role: admin (1)
  end

  test "redirects to login when not authenticated" do
    get "/dashboard/apps"
    assert_response :redirect
  end

  test "shows apps index when authenticated" do
    sign_in @user
    get "/dashboard/apps"
    assert_response :success
  end
end

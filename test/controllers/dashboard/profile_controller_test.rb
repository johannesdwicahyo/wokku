require "test_helper"

class Dashboard::ProfileControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:two)  # role: admin (1)
  end

  test "redirects to login when not authenticated" do
    get "/dashboard/profile"
    assert_response :redirect
  end

  test "shows profile when authenticated" do
    sign_in @user
    get "/dashboard/profile"
    assert_response :success
  end
end

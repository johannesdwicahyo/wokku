require "test_helper"

class Dashboard::ActivitiesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:two)   # role: admin (1)
  end

  # ---------------------------------------------------------------------------
  # index (GET /dashboard/activities)
  # ---------------------------------------------------------------------------

  test "index: redirects when not authenticated" do
    get "/dashboard/activities"
    assert_response :redirect
  end

  test "index: returns 200 when authenticated" do
    sign_in @user
    get "/dashboard/activities"
    assert_response :success
  end

  test "index: member (role 0) can access activities" do
    sign_in users(:one)
    get "/dashboard/activities"
    assert_response :success
  end
end

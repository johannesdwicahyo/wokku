require "test_helper"

class Dashboard::TeamsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  # Pre-launch: the dashboard Teams UI is hidden behind a redirect to
  # /dashboard. The Team model + memberships stay intact for future
  # multi-user work; only the UI surface is gone.
  test "GET /dashboard/teams redirects to dashboard" do
    sign_in users(:one)
    get "/dashboard/teams"
    assert_redirected_to "/dashboard"
  end

  test "GET /dashboard/teams/anything redirects to dashboard" do
    sign_in users(:one)
    get "/dashboard/teams/123"
    assert_redirected_to "/dashboard"
  end
end

require "test_helper"

# Smoke test: each top-level dashboard page must render without 500.
# Catches broken layout/navbar/sidebar partials — the class of bug that
# static analysis and controller tests (which often skip shared layouts)
# can miss.
class DashboardSmokeTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  PAGES = %w[
    /dashboard
    /dashboard/apps
    /dashboard/servers
    /dashboard/resources
    /dashboard/templates
    /dashboard/teams
    /dashboard/notifications
    /dashboard/activities
    /dashboard/profile
    /dashboard/billing
  ].freeze

  setup do
    @user = users(:one) # regular user, skips admin 2FA enforcement
    sign_in @user
  end

  PAGES.each do |path|
    test "GET #{path} renders without error" do
      get path
      assert_includes [ 200, 302 ], response.status,
        "#{path} returned #{response.status}\n#{response.body[0, 500]}"
    end
  end
end

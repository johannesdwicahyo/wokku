require "rails_helper"

# Smoke test: each top-level dashboard page must render without 500.
# Catches broken layout/navbar/sidebar partials -- the class of bug that
# static analysis and controller tests (which often skip shared layouts)
# can miss.
RSpec.describe "Dashboard smoke", type: :request do
  include Devise::Test::IntegrationHelpers

  # /dashboard/servers moved to the admin namespace; regular users no
  # longer have a top-level servers page. /dashboard returns a 301 to
  # the apps dashboard; /dashboard/addons returns a 301 to apps.
  PAGES = %w[
    /dashboard
    /dashboard/apps
    /dashboard/addons
    /dashboard/templates
    /dashboard/notifications
    /dashboard/activities
    /dashboard/profile
    /dashboard/billing
  ].freeze

  let(:user) { users(:one) } # regular user, skips admin 2FA enforcement

  before { sign_in user }

  PAGES.each do |path|
    it "GET #{path} renders without error" do
      get path
      # 200 ok, 301 permanent (route-level redirect, e.g. /dashboard →
      # /dashboard/apps), 302 found (controller-level redirect).
      expect([ 200, 301, 302 ]).to include(response.status),
        "#{path} returned #{response.status}\n#{response.body[0, 500]}"
    end
  end
end

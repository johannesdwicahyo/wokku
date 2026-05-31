# frozen_string_literal: true

require "rails_helper"

# Visual smoke for the dashboard — runs as a request spec (rack_test, no JS)
# to exercise every major page through the full controller stack.
# If a page raises a 5xx we want to know about it here before opening a PR.
# If a controller crashes, DO NOT fix it here — report the failure instead.
RSpec.describe "Dashboard visual smoke", type: :request do
  include Devise::Test::IntegrationHelpers
  include Rails.application.routes.url_helpers

  let(:solo_plan) do
    Plan.find_by(key: "solo") ||
      Plan.find_or_create_by!(key: "solo") do |p|
        p.name = "Solo"
        p.price_usd_cents = 500
        p.price_idr = 0
        p.seats_included = 1
        p.box_quotas = { "small" => 3, "sleeping" => 3 }
        p.backup_policy = "daily"
        p.backup_retention_days = 3
        p.support_level = "email"
        p.pro_features = []
        p.addons_available = {}
      end
  end

  let(:user) { create(:user, plan: solo_plan) }
  let(:team) do
    t = create(:team, owner: user)
    create(:team_membership, team: t, user: user, role: :admin)
    t
  end
  # Named `the_app` to avoid shadowing rack-test's internal `app` method,
  # which would cause "undefined method 'call' for AppRecord" errors.
  let(:the_app) { create(:app_record, team: team) }

  before do
    # Seed the 4 canonical plans so views referencing them don't blow up.
    %w[free solo pro team].each do |key|
      Plan.find_or_create_by!(key: key) do |p|
        p.name = key.capitalize
        p.price_usd_cents = 0
        p.price_idr = 0
        p.seats_included = 1
        p.box_quotas = {}
        p.backup_policy = "manual"
        p.backup_retention_days = 0
        p.support_level = "chatbot"
        p.pro_features = []
        p.addons_available = {}
      end
    end

    sign_in user
  end

  %w[/dashboard/apps /dashboard/templates /dashboard/billing /dashboard/profile].each do |path|
    it "renders #{path} without a 5xx" do
      get path
      follow_redirect! while response.redirect?
      expect(response.status).to be < 500
    end
  end

  it "renders app show (overview tab) without a 5xx" do
    get dashboard_app_path(the_app)
    follow_redirect! while response.redirect?
    expect(response.status).to be < 500
    expect(response.body).to match(/overview/i)
  end

  it "redirects /dashboard → /dashboard/apps" do
    get "/dashboard"
    expect(response).to redirect_to("/dashboard/apps")
  end
end

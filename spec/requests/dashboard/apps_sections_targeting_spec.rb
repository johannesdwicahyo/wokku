# frozen_string_literal: true

require "rails_helper"

# Regression (2026-06-09): the apps index table renders inside the
# `apps_list` deferred turbo-frame. Without target="_top", clicking an
# app link navigated WITHIN the frame (fetching the app-show page, which
# has no apps_list frame) instead of doing a full-page visit. The frame
# must break its links out to the top level, and section responses must
# not be cached (the stale-cache "Content missing" symptom).
RSpec.describe "Dashboard::Apps deferred section targeting", type: :request do
  include Devise::Test::IntegrationHelpers

  before { sign_in users(:one) }

  it "renders the apps_list frame with target=_top so links do full-page visits" do
    get sections_dashboard_apps_path(section: :list)
    expect(response.body).to match(/<turbo-frame[^>]*id="apps_list"[^>]*target="_top"/)
  end

  it "marks deferred section responses as no-store (never cached)" do
    get sections_dashboard_apps_path(section: :list)
    expect(response.headers["Cache-Control"]).to include("no-store")
  end

  it "renders the shell placeholder for apps_list with target=_top" do
    get dashboard_apps_path
    expect(response.body).to match(/<turbo-frame[^>]*id="apps_list"[^>]*target="_top"/)
  end
end

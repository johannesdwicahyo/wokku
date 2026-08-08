# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::Teams legacy redirect", type: :request do
  include Devise::Test::IntegrationHelpers

  # Pre-launch the Teams UI redirected to /dashboard. PR C of the
  # personal+multi-team refactor (2026-05-28) repointed the redirect
  # at the new /dashboard/workspaces index so external links stay
  # alive but reach the canonical surface.
  it "GET /dashboard/teams redirects to /dashboard/workspaces" do
    sign_in users(:one)
    get "/dashboard/teams"
    expect(response).to redirect_to("/dashboard/workspaces")
  end

  it "GET /dashboard/teams/anything redirects to /dashboard/workspaces" do
    sign_in users(:one)
    get "/dashboard/teams/123"
    expect(response).to redirect_to("/dashboard/workspaces")
  end
end

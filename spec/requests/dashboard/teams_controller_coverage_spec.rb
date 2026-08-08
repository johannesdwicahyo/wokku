# frozen_string_literal: true

require "rails_helper"

# Dashboard::TeamsController is no longer wired to a resourceful route — PR C
# of the personal+multi-team refactor (2026-05-28) repointed /dashboard/teams
# at a redirect to /dashboard/workspaces, so the controller's index/show/new/
# create actions are unreachable through the app's own route table (the existing
# teams_controller_spec.rb only exercises that redirect).
#
# To get genuine request-level coverage of the still-live controller code we
# append a temporary resourceful route for the duration of this file. The route
# name (`dashboard_teams` / `dashboard_team`) matches the path helpers the views
# call, so index/show/new render correctly. Routes are restored in after(:all).
RSpec.describe "Dashboard::TeamsController (appended test route)", type: :request do
  include Devise::Test::IntegrationHelpers

  # Append (not draw) so the real route table — including the dashboard
  # layout's `dashboard_apps_path` etc. — stays intact. reload_routes!
  # re-runs config/routes.rb and then applies this appended block.
  before(:all) do
    Rails.application.routes.append do
      namespace :dashboard do
        resources :teams_live, only: %i[index show new create],
                              controller: "teams",
                              path: "teams_live",
                              as: :teams
      end
    end
    Rails.application.reload_routes!
  end

  after(:all) do
    # Drop the appended block and restore the canonical route table.
    Rails.application.routes_reloader.paths.each { |path| load(path) }
    Rails.application.routes.instance_variable_get(:@append).clear
    Rails.application.reload_routes!
  end

  let(:user) { users(:one) }
  let(:other_user) { users(:two) }

  before { sign_in user }

  describe "GET index" do
    it "renders the teams the user belongs to" do
      get "/dashboard/teams_live"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(teams(:one).name)
    end

    it "does not list teams the user has no membership on (policy scope)" do
      get "/dashboard/teams_live"
      expect(response.body).not_to include(teams(:two).name)
    end
  end

  describe "GET show" do
    it "renders a team the user is a member of, listing members" do
      get "/dashboard/teams_live/#{teams(:one).id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(user.email)
    end

    it "is forbidden for a team the user has no membership on (Pundit -> root redirect)" do
      get "/dashboard/teams_live/#{teams(:two).id}"
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("You are not authorized to perform this action.")
    end

    it "renders the 404 page for an unknown team id (RecordNotFound)" do
      get "/dashboard/teams_live/#{SecureRandom.uuid}"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET new" do
    it "renders the blank team form" do
      get "/dashboard/teams_live/new"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("new_team")
    end
  end

  describe "POST create" do
    it "creates a team owned by the current user plus an admin membership, then redirects" do
      expect {
        post "/dashboard/teams_live", params: { team: { name: "Coverage Crew" } }
      }.to change(Team, :count).by(1)

      created = Team.find_by(name: "Coverage Crew")
      expect(created.owner).to eq(user)
      expect(TeamMembership.exists?(user: user, team: created, role: "admin")).to be(true)
      # The controller redirects to dashboard_teams_path; in the live app that
      # name resolves to the /dashboard/teams redirect route.
      expect(response).to redirect_to(dashboard_teams_path)
      expect(flash[:notice]).to eq("Team created successfully.")
    end

    it "re-renders index with 422 when the team is invalid (blank name)" do
      expect {
        post "/dashboard/teams_live", params: { team: { name: "" } }
      }.not_to change(Team, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end

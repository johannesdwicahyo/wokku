# frozen_string_literal: true

require "rails_helper"

# The record panel (U3): a read-only drawer opened from an apps-table row.
# GET .../panel renders the shell + header; the deploys/logs body sections
# are lazy turbo-frames served through the existing Deferrable `section`
# route (collection-scoped, app_id passed as a query param).
RSpec.describe "Dashboard::Apps#panel", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user)        { users(:two) }          # member of team two
  let(:outsider)    { users(:one) }          # member of a different team
  let(:target_app)  { app_records(:two) }    # belongs to team two — NEVER name this `app`:
  # that identifier is reserved by Rails integration tests for the Rack app
  # under test; shadowing it silently breaks route-helper resolution.

  it "redirects to login when unauthenticated" do
    get panel_dashboard_app_path(target_app)
    expect(response).to have_http_status(:redirect)
  end

  context "when signed in as a team member" do
    before { sign_in user }

    it "renders the panel with the record-panel turbo-frame and the app name" do
      get panel_dashboard_app_path(target_app)

      expect(response).to have_http_status(:success)
      expect(response.body).to include('<turbo-frame id="app_record_panel"')
      expect(response.body).to include(target_app.name)
    end
  end

  context "when signed in as a user outside the app's team" do
    before { sign_in outsider }

    it "does not allow viewing the panel" do
      get panel_dashboard_app_path(target_app)
      expect(response).not_to have_http_status(:success)
    end
  end

  context "deferred sections" do
    before { sign_in user }

    it "renders the panel_deploys section as a turbo-frame" do
      get sections_dashboard_apps_path(section: :panel_deploys, app_id: target_app.id)
      expect(response).to have_http_status(:success)
      expect(response.body).to include("<turbo-frame id=\"app_panel_deploys_#{target_app.id}\"")
    end

    it "renders the panel_logs section as a turbo-frame" do
      get sections_dashboard_apps_path(section: :panel_logs, app_id: target_app.id)
      expect(response).to have_http_status(:success)
      expect(response.body).to include("<turbo-frame id=\"app_panel_logs_#{target_app.id}\"")
    end

    it "returns 404 for an unknown app_id" do
      get sections_dashboard_apps_path(section: :panel_deploys, app_id: "00000000-0000-0000-0000-000000000000")
      expect(response).to have_http_status(:not_found)
    end
  end
end

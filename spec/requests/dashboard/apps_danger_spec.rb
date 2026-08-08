# frozen_string_literal: true

require "rails_helper"

# The Danger Zone settings section surfaces the (previously orphaned) app
# destroy action in the dashboard UI. The DELETE route + controller action
# already existed; only the GET page that renders the delete form was missing.
RSpec.describe "Dashboard::Apps#danger", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin)      { users(:two) }              # team-admin of team two
  let(:outsider)   { users(:one) }              # admin of a different team
  let(:target_app) { app_records(:two) }        # belongs to team two

  it "redirects to login when not authenticated" do
    get danger_dashboard_app_path(target_app)
    expect(response).to have_http_status(:redirect)
    expect(response).to redirect_to(new_user_session_path)
  end

  context "as a team admin" do
    before { sign_in admin }

    it "renders the danger zone with a delete form pointing at destroy" do
      get danger_dashboard_app_path(target_app)

      expect(response).to have_http_status(:success)
      # Form posts to the existing destroy route via DELETE.
      expect(response.body).to include(dashboard_app_path(target_app))
      expect(response.body).to match(/name="_method"\s+(?:type="hidden"\s+)?value="delete"/)
      # Wired to the type-to-confirm Stimulus controller.
      expect(response.body).to include("confirm-delete")
      expect(response.body).to include(target_app.name)
    end
  end

  context "as a user who is not a member of the app's team" do
    before { sign_in outsider }

    it "does not allow viewing the danger zone" do
      get danger_dashboard_app_path(target_app)
      expect(response).not_to have_http_status(:success)
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

# Inline `deploy_branch` edit (U5 Task 2, locked decision #1: the ONE safe
# inline-editable field in the record panel). Plain AppRecord column, no
# fleet side effects — only affects the next deploy. Follows the
# apps_panel_spec.rb idiom (owner vs. foreign-team authz).
RSpec.describe "Dashboard::Apps#update_deploy_branch", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user)       { users(:two) }        # member of team two
  let(:outsider)   { users(:one) }        # member of a different team
  let(:target_app) { app_records(:two) }  # belongs to team two

  context "when signed in as a team member" do
    before { sign_in user }

    it "updates the branch and persists it" do
      patch deploy_branch_dashboard_app_path(target_app), params: { app_record: { deploy_branch: "release" } }

      expect(target_app.reload.deploy_branch).to eq("release")
      expect(response).to have_http_status(:redirect)
    end

    it "ignores unpermitted params (e.g. name)" do
      patch deploy_branch_dashboard_app_path(target_app), params: { app_record: { deploy_branch: "release", name: "hijacked" } }

      target_app.reload
      expect(target_app.deploy_branch).to eq("release")
      expect(target_app.name).not_to eq("hijacked")
    end

    it "leaves the branch unchanged when submitted blank" do
      patch deploy_branch_dashboard_app_path(target_app), params: { app_record: { deploy_branch: "" } }
      expect(target_app.reload.deploy_branch).to eq("main")
    end
  end

  context "when signed in as a user outside the app's team" do
    before { sign_in outsider }

    it "does not allow updating a foreign app's branch" do
      patch deploy_branch_dashboard_app_path(target_app), params: { app_record: { deploy_branch: "release" } }

      expect(response).to have_http_status(:redirect)
      expect(target_app.reload.deploy_branch).to eq("main")
    end
  end

  context "when not authenticated" do
    it "redirects to login" do
      patch deploy_branch_dashboard_app_path(target_app), params: { app_record: { deploy_branch: "release" } }
      expect(response).to have_http_status(:redirect)
      expect(target_app.reload.deploy_branch).to eq("main")
    end
  end
end

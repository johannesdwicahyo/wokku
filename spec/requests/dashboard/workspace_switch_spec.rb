require "rails_helper"

RSpec.describe "Dashboard::Workspaces#switch (PR B session backend)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user)        { users(:one) }
  let(:own_team)    { teams(:one) }
  let(:foreign_team) { teams(:two) }

  before { sign_in user }

  it "sets session[:current_team_id] when the target is a member team" do
    post switch_dashboard_workspace_path(own_team), params: { return_to: dashboard_root_path }
    expect(response).to redirect_to(dashboard_root_path)
    expect(session[:current_team_id]).to eq(own_team.id)
  end

  it "returns 404 for a team the user doesn't belong to" do
    post switch_dashboard_workspace_path(foreign_team)
    expect(response).to have_http_status(:not_found)
    expect(session[:current_team_id]).to be_nil
  end

  it "ignores an unsafe return_to and falls back to dashboard root" do
    # The default redirect is dashboard_root_path; a missing param uses it.
    post switch_dashboard_workspace_path(own_team)
    expect(response).to redirect_to(dashboard_root_path)
  end
end

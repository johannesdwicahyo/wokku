require "rails_helper"

RSpec.describe "Dashboard::Workspaces (PR C)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { users(:one) }

  before { sign_in user }

  describe "GET /dashboard/workspaces" do
    it "renders the list of the user's teams with current marked" do
      get dashboard_workspaces_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include(teams(:one).name)
      expect(response.body).to include("current")
    end
  end

  describe "GET /dashboard/workspaces/new" do
    it "renders the create form with paid plans as radio options" do
      get new_dashboard_workspace_path
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Solo")
      expect(response.body).to include("Pro")
      expect(response.body).to include("Team")
      expect(response.body).not_to include(">Free<") # Free isn't selectable here
    end
  end

  describe "POST /dashboard/workspaces" do
    let(:pro) { Plan.find_by!(key: "pro") }
    let(:free) { Plan.find_by!(key: "free") }

    it "creates an org team with the chosen plan, sets session, and redirects" do
      expect {
        post dashboard_workspaces_path, params: { team: { name: "Agency X", plan_id: pro.id } }
      }.to change { Team.count }.by(1)
      created = Team.find_by(name: "Agency X")
      expect(created.kind).to eq("org")
      expect(created.plan_id).to eq(pro.id)
      expect(created.owner).to eq(user)
      expect(TeamMembership.exists?(user: user, team: created, role: "admin")).to be(true)
      expect(session[:current_team_id]).to eq(created.id)
      expect(response).to redirect_to(dashboard_root_path)
    end

    it "rejects creation on the Free plan" do
      expect {
        post dashboard_workspaces_path, params: { team: { name: "Agency Free", plan_id: free.id } }
      }.not_to change { Team.count }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("require a paid plan")
    end

    it "rejects a hidden non-selectable plan (e.g. the cloud's Rp0 usage plan)" do
      # "usage" is a cloud-only key (engine key validation rejects it) — insert raw.
      usage = Plan.find_by(key: "usage") || build(:plan, key: "usage", name: "Usage").tap { |p| p.save!(validate: false) }
      expect {
        post dashboard_workspaces_path, params: { team: { name: "Agency Usage", plan_id: usage.id } }
      }.not_to change { Team.count }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("require a paid plan")
    end

    it "rejects creation with a blank name" do
      expect {
        post dashboard_workspaces_path, params: { team: { name: "", plan_id: pro.id } }
      }.not_to change { Team.count }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to match(/can.{1,5}t be blank/) # html-encoded apostrophe variants
    end

    # Twin of the OAuth-signup 422: teams.name is globally UNIQUE, so a
    # workspace name already in use made Team.create! raise RecordInvalid ->
    # generic 422 page. It must render the form with a friendly message.
    it "shows a friendly error (not a raw exception page) when the name is already taken" do
      create(:team, owner: create(:user), kind: :org, plan: pro, name: "Taken Name")
      expect {
        post dashboard_workspaces_path, params: { team: { name: "Taken Name", plan_id: pro.id } }
      }.not_to change { Team.count }
      expect(response).to have_http_status(:unprocessable_entity)
      # Graceful path: re-renders the workspace form with our flash message,
      # NOT the unhandled-exception page.
      expect(response.body).not_to include("Exception caught")
      expect(response.body).to match(/already taken.*try another/i)
    end
  end
end

require "rails_helper"

RSpec.describe "Dashboard::TeamMembers (PR C2)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:owner)      { users(:one) }
  let(:team_plan)  { Plan.find_by!(key: "team") }
  let(:solo_plan)  { Plan.find_by!(key: "solo") }
  let!(:workspace) do
    Team.create!(name: "Agency X", owner: owner, kind: :org, slug: "agency-x", plan: team_plan).tap do |t|
      TeamMembership.create!(user: owner, team: t, role: :admin)
    end
  end

  let(:existing_member) { users(:two) }

  before { sign_in owner }

  describe "POST /dashboard/workspaces/:id/members (add)" do
    it "adds an existing user by email" do
      expect {
        post dashboard_workspace_team_members_path(workspace),
             params: { team_membership: { email: existing_member.email, role: "member" } }
      }.to change { workspace.team_memberships.count }.by(1)
      added = workspace.team_memberships.find_by(user: existing_member)
      expect(added.role).to eq("member")
    end

    it "rejects unknown email with a clear alert" do
      expect {
        post dashboard_workspace_team_members_path(workspace),
             params: { team_membership: { email: "nobody@nowhere.test", role: "member" } }
      }.not_to change { workspace.team_memberships.count }
      follow_redirect!
      expect(response.body).to include("ask them to sign up first")
    end

    it "is idempotent when adding an existing member" do
      TeamMembership.create!(user: existing_member, team: workspace, role: :member)
      expect {
        post dashboard_workspace_team_members_path(workspace),
             params: { team_membership: { email: existing_member.email, role: "admin" } }
      }.not_to change { workspace.team_memberships.count }
    end

    context "with a non-Team plan that hits the seat cap" do
      before { workspace.update!(plan: solo_plan) }

    end

    context "on the Team plan past seats_included" do
      it "allows the add (overage will be billed)" do
        # Fill up to seats_included (3): owner + 2 more.
        2.times do |i|
          extra = User.create!(email: "extra-#{i}-#{SecureRandom.hex(2)}@test", password: "supersecret123")
          TeamMembership.create!(user: extra, team: workspace, role: :member)
        end
        expect(workspace.team_memberships.count).to eq(team_plan.seats_included)

        expect {
          post dashboard_workspace_team_members_path(workspace),
               params: { team_membership: { email: existing_member.email, role: "member" } }
        }.to change { workspace.team_memberships.count }.by(1)
      end
    end
  end

  describe "PATCH /dashboard/workspaces/:id/members/:mid (update role)" do
    let!(:membership) { TeamMembership.create!(user: existing_member, team: workspace, role: :member) }

    it "promotes a member to admin" do
      patch dashboard_workspace_team_member_path(workspace, membership),
            params: { team_membership: { role: "admin" } }
      expect(membership.reload.role).to eq("admin")
    end

    it "stops the last admin from self-demoting" do
      owner_membership = workspace.team_memberships.find_by(user: owner)
      patch dashboard_workspace_team_member_path(workspace, owner_membership),
            params: { team_membership: { role: "member" } }
      expect(owner_membership.reload.role).to eq("admin")
      follow_redirect!
      expect(response.body).to include("last admin")
    end
  end

  describe "DELETE /dashboard/workspaces/:id/members/:mid (remove)" do
    let!(:membership) { TeamMembership.create!(user: existing_member, team: workspace, role: :member) }

    it "removes a non-owner member" do
      expect {
        delete dashboard_workspace_team_member_path(workspace, membership)
      }.to change { workspace.team_memberships.count }.by(-1)
    end

    it "blocks removing the owner" do
      owner_membership = workspace.team_memberships.find_by(user: owner)
      expect {
        delete dashboard_workspace_team_member_path(workspace, owner_membership)
      }.not_to change { workspace.team_memberships.count }
    end
  end

  describe "non-admin access" do
    let(:non_admin) { existing_member }
    before do
      TeamMembership.create!(user: non_admin, team: workspace, role: :member)
      sign_out owner
      sign_in non_admin
    end

    it "redirects with admin-only alert on add attempt" do
      post dashboard_workspace_team_members_path(workspace),
           params: { team_membership: { email: "x@y.test" } }
      expect(response).to redirect_to(dashboard_workspace_path(workspace))
      follow_redirect!
      expect(response.body).to include("Admin-only")
    end
  end
end

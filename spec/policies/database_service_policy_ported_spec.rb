require "rails_helper"

RSpec.describe DatabaseServicePolicy, type: :policy do
  let!(:owner) { User.create!(email: "ds-owner@example.com", password: "password123456") }
  let!(:team) do
    t = Team.create!(name: "DS Team", owner: owner)
    TeamMembership.create!(user: owner, team: t, role: :admin)
    t
  end
  let!(:server) { Server.create!(name: "ds-server", host: "10.0.0.2") }
  let!(:app) { AppRecord.create!(name: "ds-app", server: server, team: team, creator: owner) }
  let!(:ds) { DatabaseService.create!(name: "ds-redis", server: server, service_type: "redis", status: :running) }
  let!(:app_db) { AppDatabase.create!(app_record: app, database_service: ds, alias_name: "ds-redis") }

  let!(:member) do
    u = User.create!(email: "ds-member@example.com", password: "password123456")
    TeamMembership.create!(user: u, team: team, role: :member)
    u
  end

  let!(:outsider) do
    u = User.create!(email: "ds-outsider@example.com", password: "password123456")
    Team.create!(name: "Outsider", owner: u).team_memberships.create!(user: u, role: :admin)
    u
  end

  let(:sysadmin) { users(:admin) }

  describe "Scope" do
    it "returns services linked to user's team apps" do
      visible = DatabaseServicePolicy::Scope.new(member, DatabaseService).resolve
      expect(visible.to_a).to include(ds)
    end

    it "excludes services not linked to user's team" do
      visible = DatabaseServicePolicy::Scope.new(outsider, DatabaseService).resolve
      expect(visible.to_a).not_to include(ds)
    end

    it "returns everything for a system admin" do
      visible = DatabaseServicePolicy::Scope.new(sysadmin, DatabaseService).resolve
      expect(visible.to_a).to include(ds)
    end

    it "returns creator-owned services even with no app links" do
      orphan = DatabaseService.create!(
        name: "orphan-pg-#{SecureRandom.hex(2)}",
        server: server, service_type: "postgres", status: :creating, creator: member
      )
      visible = DatabaseServicePolicy::Scope.new(member, DatabaseService).resolve
      expect(visible.to_a).to include(orphan)
    end

    it "hides creator-owned services from outsiders" do
      orphan = DatabaseService.create!(
        name: "outsider-pg-#{SecureRandom.hex(2)}",
        server: server, service_type: "postgres", status: :creating, creator: member
      )
      visible = DatabaseServicePolicy::Scope.new(outsider, DatabaseService).resolve
      expect(visible.to_a).not_to include(orphan)
    end
  end

  describe "#show?" do
    it "is true for a team member" do
      expect(DatabaseServicePolicy.new(member, ds).show?).to be true
    end

    it "is false for an outsider" do
      expect(DatabaseServicePolicy.new(outsider, ds).show?).to be_falsey
    end

    it "is true for a system admin" do
      expect(DatabaseServicePolicy.new(sysadmin, ds).show?).to be true
    end

    it "is true for the creator even before any app link exists" do
      orphan = DatabaseService.create!(
        name: "orphan-show-#{SecureRandom.hex(2)}",
        server: server, service_type: "postgres", status: :creating, creator: member
      )
      expect(DatabaseServicePolicy.new(member, orphan).show?).to be true
    end
  end

  describe "#destroy?" do
    it "is true for a team admin via the linked app" do
      expect(DatabaseServicePolicy.new(owner, ds).destroy?).to be true
    end

    it "is false for a plain team member" do
      expect(DatabaseServicePolicy.new(member, ds).destroy?).to be_falsey
    end

    it "is true for a system admin even without team membership" do
      expect(DatabaseServicePolicy.new(sysadmin, ds).destroy?).to be true
    end
  end

  describe "#update?" do
    it "denies a team viewer (restore overwrites live data)" do
      viewer = User.create!(email: "ds-viewer@example.com", password: "password123456")
      TeamMembership.create!(user: viewer, team: team, role: :viewer)
      expect(DatabaseServicePolicy.new(viewer, ds).update?).to be_falsey
    end

    it "allows a team member" do
      expect(DatabaseServicePolicy.new(member, ds).update?).to be(true)
    end

    it "denies an outsider" do
      expect(DatabaseServicePolicy.new(outsider, ds).update?).to be_falsey
    end
  end
end

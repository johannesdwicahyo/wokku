require "rails_helper"

RSpec.describe DomainPolicy, type: :policy do
  let!(:owner) { User.create!(email: "domain-policy-owner@example.com", password: "password123456") }
  let!(:team) do
    t = Team.create!(name: "Domain Policy Team", owner: owner)
    TeamMembership.create!(user: owner, team: t, role: :admin)
    t
  end
  let!(:server) { Server.create!(name: "dp-server", host: "10.0.0.1", team: team) }
  let!(:app) { AppRecord.create!(name: "dp-app", server: server, team: team, creator: owner) }
  let!(:domain) { app.domains.create!(hostname: "dp.example.com", ssl_enabled: false) }

  let!(:member) do
    u = User.create!(email: "domain-policy-member@example.com", password: "password123456")
    TeamMembership.create!(user: u, team: team, role: :member)
    u
  end

  let!(:outsider) { User.create!(email: "domain-policy-outsider@example.com", password: "password123456") }

  describe "#index?" do
    it "is always true for any user" do
      expect(DomainPolicy.new(owner, domain).index?).to be true
      expect(DomainPolicy.new(member, domain).index?).to be true
      expect(DomainPolicy.new(outsider, domain).index?).to be true
    end
  end

  describe "#create?" do
    it "is true for a team admin" do
      expect(DomainPolicy.new(owner, domain).create?).to be true
    end

    it "is true for a team member" do
      expect(DomainPolicy.new(member, domain).create?).to be true
    end

    it "is false for an outsider" do
      expect(DomainPolicy.new(outsider, domain).create?).to be false
    end
  end

  describe "#destroy?" do
    it "is true for a team admin" do
      expect(DomainPolicy.new(owner, domain).destroy?).to be true
    end

    it "is true for a team member" do
      expect(DomainPolicy.new(member, domain).destroy?).to be true
    end

    it "is false for an outsider" do
      expect(DomainPolicy.new(outsider, domain).destroy?).to be false
    end
  end

  describe "#ssl?" do
    it "is true for a team admin" do
      expect(DomainPolicy.new(owner, domain).ssl?).to be true
    end

    it "is true for a team member" do
      expect(DomainPolicy.new(member, domain).ssl?).to be true
    end

    it "is false for an outsider" do
      expect(DomainPolicy.new(outsider, domain).ssl?).to be false
    end
  end

  describe "Scope" do
    it "resolves domains for the user's team only" do
      other_team = Team.create!(name: "Other DP Team", owner: outsider)
      TeamMembership.create!(user: outsider, team: other_team, role: :admin)
      other_server = Server.create!(name: "other-dp-srv", host: "9.9.9.9", team: other_team)
      other_app = AppRecord.create!(name: "other-dp-app", server: other_server, team: other_team, creator: outsider)
      other_domain = other_app.domains.create!(hostname: "other-dp.example.com", ssl_enabled: false)

      scope = DomainPolicy::Scope.new(owner, Domain.all).resolve
      expect(scope).to include(domain)
      expect(scope).not_to include(other_domain)
    end
  end
end

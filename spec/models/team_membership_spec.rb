require "rails_helper"

RSpec.describe TeamMembership do
  let(:owner) { User.create!(email: "membership-owner@example.com", password: "password123456") }
  let(:team) { Team.create!(name: "membership-team", owner: owner) }
  let(:user) { User.create!(email: "membership-user@example.com", password: "password123456") }

  it "is valid" do
    membership = TeamMembership.new(user: user, team: team, role: :member)
    expect(membership).to be_valid
  end

  it "defaults role to viewer" do
    membership = TeamMembership.new(user: user, team: team)
    expect(membership.role).to eq("viewer")
  end

  it "user can only belong to a team once" do
    TeamMembership.create!(user: user, team: team, role: :member)
    duplicate = TeamMembership.new(user: user, team: team, role: :admin)
    expect(duplicate).not_to be_valid
  end

  it "exposes role enum values" do
    expect(TeamMembership.roles[:viewer]).to eq(0)
    expect(TeamMembership.roles[:member]).to eq(1)
    expect(TeamMembership.roles[:admin]).to eq(2)
  end
end

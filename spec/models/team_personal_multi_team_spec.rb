require "rails_helper"

RSpec.describe Team, "personal + multi-team additions (PR A)" do
  let(:user) { users(:one) }

  describe "kind enum" do
    it "exposes personal? and org? predicates" do
      team = Team.new(kind: :personal)
      expect(team.personal?).to be(true)
      expect(team.org?).to be(false)

      team.kind = :org
      expect(team.personal?).to be(false)
      expect(team.org?).to be(true)
    end

    it "uses prefix: true so the scope is kind_personal / kind_org" do
      expect(Team).to respond_to(:kind_personal)
      expect(Team).to respond_to(:kind_org)
    end
  end

  describe "slug validation" do
    let(:plan) { Plan.find_by!(key: "free") }

    it "rejects non-kebab slugs" do
      team = Team.new(name: "Bad Slug", owner: user, kind: :personal, plan: plan, slug: "Has Spaces")
      expect(team).not_to be_valid
      expect(team.errors[:slug]).to be_present
    end

    it "accepts lowercase alphanumeric with hyphens" do
      team = Team.new(name: "Good Slug", owner: user, kind: :personal, plan: plan, slug: "my-team-1")
      expect(team).to be_valid
    end

    it "enforces uniqueness case-insensitively" do
      Team.create!(name: "Dup A", owner: user, kind: :personal, plan: plan, slug: "dup-team")
      dup = Team.new(name: "Dup B", owner: user, kind: :personal, plan: plan, slug: "DUP-TEAM")
      expect(dup).not_to be_valid
      expect(dup.errors[:slug]).to be_present
    end
  end

  describe "User#personal_team" do
    it "returns the user's :personal team" do
      expect(user.personal_team).to eq(teams(:one))
    end
  end
end

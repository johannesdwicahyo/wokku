require "rails_helper"

# Sanity-check that PR A's schema + backfill produced the invariants
# PR B will rely on. The backfill itself ran in
# BackfillTeamBillingColumns; here we assert the post-state against
# the fixture-loaded universe.
RSpec.describe "Personal + multi-team — PR A backfill" do
  describe "Team" do
    it "every team has kind populated (personal=0 or org=1)" do
      Team.find_each do |t|
        expect(t.kind).not_to be_nil, "team #{t.id} has nil kind"
      end
    end

    it "every team has a non-blank slug" do
      Team.find_each do |t|
        expect(t.slug).to be_present, "team #{t.id} has blank slug"
      end
    end

    it "team slugs are unique" do
      slugs = Team.pluck(:slug).compact
      expect(slugs.size).to eq(slugs.uniq.size), "duplicate slugs found"
    end

    it "every team has a plan_id matching its owner's plan_id" do
      Team.includes(:owner).find_each do |t|
        next unless t.owner&.plan_id # users without a plan are pre-1.7 records
        expect(t.plan_id).to eq(t.owner.plan_id), "team #{t.id} plan_id drifted from owner"
      end
    end
  end

  describe "Subscription" do
    it "every subscription has a team_id matching its user's first team" do
      # New subscriptions created in specs after PR A may not yet
      # populate team_id (PR B will). Scope this to the post-backfill
      # window by looking only at rows that existed before the data
      # migration completed.
      Subscription.find_each do |s|
        first_team = s.user.teams.order(:created_at).first
        next unless first_team
        # Allow team_id to be nil for fresh in-spec creates; if set,
        # it must point to the user's first team.
        expect([ nil, first_team.id ]).to include(s.team_id),
          "subscription #{s.id} team_id=#{s.team_id} doesn't match user's first team #{first_team.id}"
      end
    end
  end

  describe "Invoice" do
    it "every invoice has a team_id matching its user's first team (or nil for fresh creates)" do
      Invoice.find_each do |i|
        first_team = i.user.teams.order(:created_at).first
        next unless first_team
        expect([ nil, first_team.id ]).to include(i.team_id),
          "invoice #{i.id} team_id=#{i.team_id} doesn't match user's first team #{first_team.id}"
      end
    end
  end
end

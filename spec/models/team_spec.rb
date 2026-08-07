require "rails_helper"

RSpec.describe Team do
  let(:owner) { User.create!(email: "team-owner@example.com", password: "password123456") }

  it "is valid with name and owner" do
    team = Team.new(name: "my-team", owner: owner)
    expect(team).to be_valid
  end

  it "requires name" do
    team = Team.new(owner: owner)
    expect(team).not_to be_valid
    expect(team.errors[:name]).to include("can't be blank")
  end

  it "requires unique name" do
    Team.create!(name: "unique-team", owner: owner)
    duplicate = Team.new(name: "unique-team", owner: owner)
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:name]).to include("has already been taken")
  end

  it "requires owner" do
    team = Team.new(name: "orphan-team")
    expect(team).not_to be_valid
    expect(team.errors[:owner]).to include("must exist")
  end

  # Phase 4 signup-defaults regression coverage — prevents the nil.prev_month
  # crash on Free → Paid upgrades.
  describe "billing defaults on create" do
    it "sets billing_anchor_date to today" do
      team = Team.create!(name: "anchored", owner: owner)
      expect(team.billing_anchor_date).to eq(Date.current)
    end

    it "sets trial_ends_at to ~7 days from now" do
      team = Team.create!(name: "trialing", owner: owner)
      expect(team.trial_ends_at).to be_within(1.minute).of(7.days.from_now)
    end

    it "leaves explicit values alone" do
      anchor = 3.days.ago.to_date
      ends   = 14.days.from_now
      team = Team.create!(name: "explicit", owner: owner,
                          billing_anchor_date: anchor, trial_ends_at: ends)
      expect(team.billing_anchor_date).to eq(anchor)
      expect(team.trial_ends_at).to be_within(1.minute).of(ends)
    end

    it "yields a non-nil next_billing_date" do
      team = Team.create!(name: "billable", owner: owner)
      expect(team.next_billing_date).to be_a(Date)
    end
  end

  describe "one personal team per owner" do
    let(:user) { create(:user) }

    it "rejects a second personal team for the same owner" do
      create(:team, owner: user, kind: :personal)
      dup = build(:team, owner: user, kind: :personal)
      expect(dup).not_to be_valid
      expect(dup.errors[:owner_id]).to be_present
    end

    it "allows an org team alongside a personal one" do
      create(:team, owner: user, kind: :personal)
      expect(build(:team, owner: user, kind: :org)).to be_valid
    end
  end
end

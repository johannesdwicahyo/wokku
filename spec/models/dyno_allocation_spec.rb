require "rails_helper"

RSpec.describe DynoAllocation do
  let(:owner)  { User.create!(email: "dyno-owner@example.com", password: "password123456") }
  let(:team)   { Team.create!(name: "dyno-team", owner: owner) }
  let(:server) { Server.create!(name: "dyno-server", host: "10.0.0.50", team: team) }
  let(:app)    { AppRecord.create!(name: "dyno-app", server: server, team: team, creator: owner) }
  let(:tier)   { dyno_tiers(:basic) }

  it "is valid" do
    alloc = DynoAllocation.new(app_record: app, dyno_tier: tier, process_type: "web", count: 1)
    expect(alloc).to be_valid
  end

  it "requires process_type" do
    alloc = DynoAllocation.new(app_record: app, dyno_tier: tier, count: 1)
    expect(alloc).not_to be_valid
    expect(alloc.errors[:process_type]).to include("can't be blank")
  end

  it "requires unique process_type per app" do
    DynoAllocation.create!(app_record: app, dyno_tier: tier, process_type: "web", count: 1)
    dup = DynoAllocation.new(app_record: app, dyno_tier: tier, process_type: "web", count: 2)
    expect(dup).not_to be_valid
  end

  it "requires non-negative count" do
    alloc = DynoAllocation.new(app_record: app, dyno_tier: tier, process_type: "web", count: -1)
    expect(alloc).not_to be_valid
  end

  it "defaults count to 1" do
    alloc = DynoAllocation.new(app_record: app, dyno_tier: tier, process_type: "web")
    expect(alloc.count).to eq(1)
  end

  it "monthly_cost_cents calculates correctly" do
    alloc = DynoAllocation.new(app_record: app, dyno_tier: tier, process_type: "web", count: 3)
    expect(alloc.monthly_cost_cents).to eq(1500)
  end

  it "is reachable via app.dyno_allocations" do
    alloc = DynoAllocation.create!(app_record: app, dyno_tier: tier, process_type: "web", count: 1)
    expect(app.dyno_allocations).to include(alloc)
  end
end

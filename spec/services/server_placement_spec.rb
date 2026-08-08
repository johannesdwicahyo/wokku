# frozen_string_literal: true

require "rails_helper"

RSpec.describe ServerPlacement do
  let(:user) { User.create!(email: "placement@example.com", password: "password123456") }
  let(:team) { Team.create!(name: "Placement Team", owner: user) }

  # "Used" capacity is no longer a stored column — it's derived from the dyno
  # memory allocated to apps on the server (Server#allocated_memory_mb). Park
  # +mb+ of allocation on +server+ so placement sees it as occupied.
  def occupy(server, mb)
    app = FactoryBot.create(:app_record, server: server, team: team)
    tier = FactoryBot.create(:dyno_tier, memory_mb: mb)
    FactoryBot.create(:dyno_allocation, app_record: app, dyno_tier: tier, count: 1)
  end

  it "ranks by free capacity (total minus allocated), not raw total" do
    # Bigger box, but nearly full of allocations → less free than the smaller box.
    big_busy = Server.create!(name: "big-busy", host: "10.0.0.10", team: team, capacity_total_mb: 4096, status: :connected)
    occupy(big_busy, 3900) # 196 free
    small_idle = Server.create!(name: "small-idle", host: "10.0.0.11", team: team, capacity_total_mb: 2048, status: :connected)
    occupy(small_idle, 100) # 1948 free

    placement = described_class.new(team: team, required_memory_mb: 100)
    expect(placement.find_best_server).to eq(small_idle)
  end

  it "excludes servers whose free capacity is below the requirement" do
    busy = Server.create!(name: "busy", host: "10.0.0.12", team: team, capacity_total_mb: 2048, status: :connected)
    occupy(busy, 1800) # only 248 free — below 512
    roomy = Server.create!(name: "roomy", host: "10.0.0.13", team: team, capacity_total_mb: 1024, status: :connected)

    placement = described_class.new(team: team, required_memory_mb: 512)
    expect(placement.find_best_server).to eq(roomy)
  end

  it "raises NoCapacityError when allocations leave no server with enough free capacity" do
    only = Server.create!(name: "only", host: "10.0.0.14", team: team, capacity_total_mb: 2048, status: :connected)
    occupy(only, 1800) # 248 free, request needs 512

    placement = described_class.new(team: team, required_memory_mb: 512)
    expect { placement.find_best_server }.to raise_error(ServerPlacement::NoCapacityError)
  end

  it "filters by region when specified" do
    us = Server.create!(name: "us-server", host: "10.0.0.15", team: team, capacity_total_mb: 4096, region: "us-east-1", status: :connected)
    Server.create!(name: "eu-server", host: "10.0.0.16", team: team, capacity_total_mb: 8192, region: "eu-west-1", status: :connected)

    placement = described_class.new(team: team, required_memory_mb: 256, region: "us-east-1")
    expect(placement.find_best_server).to eq(us)
  end

  it "excludes disconnected servers" do
    Server.create!(name: "offline", host: "10.0.0.17", team: team, capacity_total_mb: 8192, status: :unreachable)
    online = Server.create!(name: "online", host: "10.0.0.18", team: team, capacity_total_mb: 2048, status: :connected)

    placement = described_class.new(team: team, required_memory_mb: 256)
    expect(placement.find_best_server).to eq(online)
  end
end

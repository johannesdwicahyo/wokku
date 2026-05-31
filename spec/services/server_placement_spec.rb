# frozen_string_literal: true

require "rails_helper"

RSpec.describe ServerPlacement do
  let(:user) { User.create!(email: "placement@example.com", password: "password123456") }
  let(:team) { Team.create!(name: "Placement Team", owner: user) }

  it "finds server with most available capacity" do
    Server.create!(name: "small", host: "10.0.0.10", team: team, capacity_total_mb: 1024, capacity_used_mb: 900, status: :connected)
    large = Server.create!(name: "large", host: "10.0.0.11", team: team, capacity_total_mb: 4096, capacity_used_mb: 1000, status: :connected)

    placement = described_class.new(team: team, required_memory_mb: 100)
    expect(placement.find_best_server).to eq(large)
  end

  it "excludes servers without enough capacity" do
    Server.create!(name: "full", host: "10.0.0.12", team: team, capacity_total_mb: 1024, capacity_used_mb: 1000, status: :connected)
    available = Server.create!(name: "available", host: "10.0.0.13", team: team, capacity_total_mb: 2048, capacity_used_mb: 0, status: :connected)

    placement = described_class.new(team: team, required_memory_mb: 512)
    expect(placement.find_best_server).to eq(available)
  end

  it "raises NoCapacityError when no server has capacity" do
    Server.create!(name: "full", host: "10.0.0.14", team: team, capacity_total_mb: 512, capacity_used_mb: 500, status: :connected)

    placement = described_class.new(team: team, required_memory_mb: 1024)
    expect { placement.find_best_server }.to raise_error(ServerPlacement::NoCapacityError)
  end

  it "filters by region when specified" do
    us = Server.create!(name: "us-server", host: "10.0.0.15", team: team, capacity_total_mb: 4096, capacity_used_mb: 0, region: "us-east-1", status: :connected)
    Server.create!(name: "eu-server", host: "10.0.0.16", team: team, capacity_total_mb: 8192, capacity_used_mb: 0, region: "eu-west-1", status: :connected)

    placement = described_class.new(team: team, required_memory_mb: 256, region: "us-east-1")
    expect(placement.find_best_server).to eq(us)
  end

  it "excludes disconnected servers" do
    Server.create!(name: "offline", host: "10.0.0.17", team: team, capacity_total_mb: 8192, capacity_used_mb: 0, status: :unreachable)
    online = Server.create!(name: "online", host: "10.0.0.18", team: team, capacity_total_mb: 2048, capacity_used_mb: 0, status: :connected)

    placement = described_class.new(team: team, required_memory_mb: 256)
    expect(placement.find_best_server).to eq(online)
  end
end

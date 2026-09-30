# frozen_string_literal: true

require "rails_helper"

RSpec.describe DatabaseService, "#billing_team" do
  let(:server) { create(:server) }
  let(:db)     { create(:database_service, server: server, cpu: 0.25, memory_mb: 256) }

  it "bills the earliest-linked team when linked into two teams" do
    team_a = create(:team)
    team_b = create(:team)
    app_a  = create(:app_record, team: team_a, server: server)
    app_b  = create(:app_record, team: team_b, server: server)

    later_link   = create(:app_database, app_record: app_b, database_service: db)
    earlier_link = create(:app_database, app_record: app_a, database_service: db)
    later_link.update_column(:created_at, 1.day.ago)
    earlier_link.update_column(:created_at, 2.days.ago)

    expect(db.billing_team).to eq(team_a)
  end

  it "falls back to the creator's team when unlinked" do
    team = create(:team)
    create(:team_membership, team: team, user: team.owner)
    unlinked = create(:database_service, server: server, creator: team.owner, cpu: 0.25, memory_mb: 256)

    expect(unlinked.billing_team).to eq(team)
  end
end

RSpec.describe DatabaseService, "legacy tier change on a shaped row" do
  # Backfilled row: keeps tier_name, gains a shape.
  let(:db) { create(:database_service, tier_name: "basic", cpu: 0.25, memory_mb: 256, disk_gb: 5) }

  it "clears cpu/memory so the new tier governs, keeping the disk floor" do
    db.update!(tier_name: "standard")
    db.reload
    expect(db.shape).to be_nil
    expect(db.disk_gb).to eq(5)
  end

  it "keeps a shape written in the same save" do
    db.update!(tier_name: "standard", cpu: 0.5, memory_mb: 1024)
    expect(db.reload.shape.to_h.slice(:cpu, :memory_mb)).to eq(cpu: 0.5, memory_mb: 1024)
  end

  it "keeps the shape on unrelated saves" do
    db.update!(status: :stopped)
    expect(db.reload.shape).to be_present
  end
end

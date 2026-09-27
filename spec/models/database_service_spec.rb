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

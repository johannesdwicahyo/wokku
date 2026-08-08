# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API host status surfacing", type: :request do
  let(:user)       { create(:user) }
  let(:team)       { user.teams.first || create(:team, owner: user) }
  let(:server)     { create(:server, team: team) }
  let!(:app_record) { create(:app_record, team: team, server: server) }

  before do
    TeamMembership.find_or_create_by!(user: user, team: team) { |m| m.role = :admin }
    server.update_columns(heartbeat_status: "down", heartbeat_at: 3.minutes.ago)
  end

  it "tells the agent WHY an app is unreachable" do
    get api_v1_app_path(app_record), headers: api_v1_headers(user)
    expect(response.parsed_body["host_status"]).to eq("down")
    expect(response.parsed_body["host_heartbeat_at"]).to be_present
  end

  it "lists heartbeat state per server" do
    get api_v1_servers_path, headers: api_v1_headers(user)
    row = response.parsed_body.find { |s| s["id"] == server.id }
    expect(row["heartbeat_status"]).to eq("down")
  end

  it "does not leak ingest_token from servers#show" do
    get api_v1_server_path(server), headers: api_v1_headers(user)
    expect(response.parsed_body).not_to have_key("ingest_token")
  end
end

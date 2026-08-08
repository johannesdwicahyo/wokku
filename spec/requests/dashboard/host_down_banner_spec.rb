# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard host-down banner", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user)   { create(:user) } # non-admin — admins bounce to 2FA setup
  let(:team)   { create(:team, owner: user, kind: :personal) }
  let(:server) { create(:server, team: team, name: "jkt-01") }

  before do
    create(:team_membership, team: team, user: user, role: :admin)
    sign_in user
  end

  it "warns when a host running my apps is down" do
    create(:app_record, team: team, server: server)
    server.update_columns(heartbeat_status: "down", heartbeat_at: 5.minutes.ago, agent_version: "0.1.0")

    get "/dashboard/apps"
    expect(response.body).to include("host-down-banner")
    expect(response.body).to include("jkt-01")
  end

  it "stays hidden when my hosts are healthy" do
    create(:app_record, team: team, server: server)
    server.update_columns(heartbeat_status: "ok", heartbeat_at: 5.seconds.ago, agent_version: "0.1.0")

    get "/dashboard/apps"
    expect(response.body).not_to include("host-down-banner")
  end

  it "stays hidden for teams with no apps on the sick host" do
    server.update_columns(heartbeat_status: "down", agent_version: "0.1.0")
    get "/dashboard/apps"
    expect(response.body).not_to include("host-down-banner")
  end
end

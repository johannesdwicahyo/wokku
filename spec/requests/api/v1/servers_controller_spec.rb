# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API::V1::ServersController", type: :request do
  let(:admin) { users(:admin) }
  let(:user) { User.create!(email: "api-servers-test@example.com", password: "password123456") }
  let!(:server) { Server.create!(name: "prod-api-test", host: "1.2.3.4") }
  let(:admin_token) { api_v1_token_for(admin, name: "test-admin") }
  let(:user_token) { api_v1_token_for(user, name: "test-user") }
  let(:admin_headers) { { "Authorization" => "Bearer #{admin_token}" } }
  let(:user_headers) { { "Authorization" => "Bearer #{user_token}" } }

  it "index returns all platform servers to admins" do
    get api_v1_servers_path, headers: admin_headers
    expect(response).to have_http_status(:success)
    names = JSON.parse(response.body).map { |s| s["name"] }
    expect(names).to include("prod-api-test")
  end

  it "index returns servers to non-admin so CLI can pick a deploy target" do
    get api_v1_servers_path, headers: user_headers
    expect(response).to have_http_status(:success)
    names = JSON.parse(response.body).map { |s| s["name"] }
    expect(names).to include("prod-api-test")
  end

  it "show returns server details to admins" do
    get api_v1_server_path(server), headers: admin_headers
    expect(response).to have_http_status(:success)
    body = JSON.parse(response.body)
    expect(body["name"]).to eq("prod-api-test")
    expect(body["ssh_private_key"]).to be_nil
  end

  it "show returns server details to non-admin" do
    get api_v1_server_path(server), headers: user_headers
    expect(response).to have_http_status(:success)
    expect(JSON.parse(response.body)["name"]).to eq("prod-api-test")
  end

  it "never returns host credentials (show, create, index)" do
    get api_v1_server_path(server), headers: user_headers
    show_body = JSON.parse(response.body)
    post api_v1_servers_path,
      params: { name: "leak-check", host: "5.6.7.9", ssh_private_key: "FAKE-PRIVATE-KEY" },
      headers: admin_headers
    create_body = JSON.parse(response.body)
    get api_v1_servers_path, headers: user_headers
    [ show_body, create_body, *JSON.parse(response.body) ].each do |s|
      expect(s.keys).not_to include("ssh_private_key", "ingest_token")
    end
    expect(response.body).not_to include("FAKE-PRIVATE-KEY")
  end

  it "create succeeds for system admin" do
    post api_v1_servers_path,
      params: { name: "staging-api-test", host: "5.6.7.8" },
      headers: admin_headers
    expect(response).to have_http_status(:created)
    expect(JSON.parse(response.body)["name"]).to eq("staging-api-test")
  end

  it "create forbidden for non-admin" do
    post api_v1_servers_path,
      params: { name: "rogue", host: "9.9.9.9" },
      headers: user_headers
    expect(response).to have_http_status(:forbidden)
  end

  it "destroy succeeds for system admin" do
    delete api_v1_server_path(server), headers: admin_headers
    expect(response).to have_http_status(:success)
    expect(Server.exists?(server.id)).to be_falsey
  end

  it "destroy forbidden for non-admin" do
    delete api_v1_server_path(server), headers: user_headers
    expect(response).to have_http_status(:forbidden)
    expect(Server.exists?(server.id)).to be_truthy
  end

  # --- dokku passthrough (retired W7 Phase 2) ---
  it "POST dokku on server: returns 410 passthrough_retired" do
    post dokku_api_v1_server_url(server),
      params: { args: [ "version" ] }, headers: admin_headers, as: :json
    expect(response).to have_http_status(:gone)
    expect(JSON.parse(response.body)["error_code"]).to eq("passthrough_retired")
  end

  it "POST dokku on server: 403 for non-admin" do
    post dokku_api_v1_server_url(server),
      params: { args: [ "version" ] }, headers: user_headers, as: :json
    expect(response).to have_http_status(:forbidden)
  end

  # --- status (wokkud heartbeat truth, no SSH) ---
  it "GET status: connected when the heartbeat is fresh" do
    server.update_columns(heartbeat_at: 5.seconds.ago, heartbeat_status: "ok",
                          status: Server.statuses[:unreachable])
    get status_api_v1_server_path(server), headers: admin_headers
    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["connected"]).to be(true)
    expect(body["status"]).to eq("connected")
  end

  it "GET status: unreachable when the heartbeat is stale" do
    server.update_columns(heartbeat_at: 10.minutes.ago,
                          status: Server.statuses[:connected])
    get status_api_v1_server_path(server), headers: admin_headers
    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["connected"]).to be(false)
    expect(body["status"]).to eq("unreachable")
  end
end

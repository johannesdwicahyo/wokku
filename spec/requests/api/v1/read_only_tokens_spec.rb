# frozen_string_literal: true

require "rails_helper"

# Security assessment 2026-11-19, F-02: a read token can look but never
# change anything, and sees secrets masked like a team viewer.
RSpec.describe "API::V1 read-only tokens", type: :request do
  let(:user) { users(:one) }
  let(:app_record) { app_records(:one) }
  let(:database) { database_services(:one) }
  let(:read_headers) { { "Authorization" => "Bearer #{api_v1_token_for(user, scope: 'read')}" } }
  let(:full_headers) { { "Authorization" => "Bearer #{api_v1_token_for(user)}" } }

  it "can read" do
    get "/api/v1/apps", headers: read_headers
    expect(response).to have_http_status(:ok)
  end

  it "refuses every write with insufficient_scope, before the action runs" do
    expect(::Apps::EnvWriter).not_to receive(:set)
    patch "/api/v1/apps/#{app_record.id}/config", params: { vars: { A: "1" } }, headers: read_headers
    expect(response).to have_http_status(:forbidden)
    expect(JSON.parse(response.body)["error_code"]).to eq("insufficient_scope")

    expect { post "/api/v1/auth/tokens", params: { name: "x" }, headers: read_headers }
      .not_to change(ApiToken, :count)
    expect(response).to have_http_status(:forbidden)

    delete "/api/v1/apps/#{app_record.id}", headers: read_headers
    expect(response).to have_http_status(:forbidden)
    expect(app_record.reload).to be_present
  end

  it "masks config values even for a team admin" do
    app_record.env_vars.create!(key: "SECRET_KEY", value: "s3cr3t")
    get "/api/v1/apps/#{app_record.id}/config", headers: read_headers
    body = JSON.parse(response.body)
    expect(body["masked"]).to be(true)
    expect(body["config"]).to include("SECRET_KEY" => nil)
    expect(body["config"].values).to all(be_nil)

    get "/api/v1/apps/#{app_record.id}/config", headers: full_headers
    expect(JSON.parse(response.body)["config"]["SECRET_KEY"]).to eq("s3cr3t")
  end

  it "hides the database dsn" do
    database.update_columns(dsn: "postgres://u:pw@h/db")
    get "/api/v1/databases/#{database.id}", headers: read_headers
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).not_to have_key("dsn")
  end

  describe "backup download (a dump holds every secret)" do
    let(:backup) do
      destination = database.server.create_backup_destination!(enabled: true, provider: "r2", bucket: "b", access_key_id: "AK", secret_access_key: "SK")
      database.backups.create!(backup_destination: destination, status: "completed", s3_key: "k/x.gz")
    end

    before { allow_any_instance_of(Backup).to receive(:download_url).and_return("https://signed") }

    it "is refused to a read token" do
      get "/api/v1/databases/#{database.id}/backups/#{backup.id}/download", headers: read_headers
      expect(response).to have_http_status(:forbidden)
    end

    it "is refused to a team viewer" do
      viewer = create(:user).tap { |u| create(:team_membership, user: u, team: app_records(:one).team, role: :viewer) }
      get "/api/v1/databases/#{database.id}/backups/#{backup.id}/download",
          headers: { "Authorization" => "Bearer #{api_v1_token_for(viewer)}" }
      expect(response).to have_http_status(:forbidden)
    end

    it "works for a full token of a member" do
      get "/api/v1/databases/#{database.id}/backups/#{backup.id}/download", headers: full_headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["url"]).to eq("https://signed")
    end
  end
end

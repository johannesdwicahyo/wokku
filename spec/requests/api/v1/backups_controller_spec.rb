# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API::V1::BackupsController", type: :request do
  let(:user) { User.create!(email: "backups-test@example.com", password: "password123456") }
  let(:team) do
    t = Team.create!(name: "Backups Team", owner: user)
    TeamMembership.create!(user: user, team: t, role: :admin)
    t
  end
  let(:server) { Server.create!(name: "prod", host: "1.2.3.4", team: team) }
  let(:database) { DatabaseService.create!(name: "mydb", service_type: "postgres", server: server) }
  let(:plain_token) { api_v1_token_for(user) }
  let(:headers) { { "Authorization" => "Bearer #{plain_token}" } }

  it "index returns 401 without token" do
    get api_v1_database_backups_path(database)
    expect(response).to have_http_status(:unauthorized)
  end

  it "create returns 401 without token" do
    post api_v1_database_backups_path(database)
    expect(response).to have_http_status(:unauthorized)
  end

  it "index returns empty list when no backups" do
    get api_v1_database_backups_path(database), headers: headers
    expect(response).to have_http_status(:success)
    expect(JSON.parse(response.body)).to eq([])
  end

  it "create refuses a shared redis tenant with 422" do
    database.update_columns(service_type: "redis", shared: true)
    allow_any_instance_of(ServerPolicy).to receive(:update?).and_return(true)
    expect {
      post api_v1_database_backups_path(database), headers: headers
    }.not_to have_enqueued_job(BackupJob)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["error"]).to match(/Shared Redis isn't backed up/)
  end

  it "unauthenticated request is rejected" do
    get api_v1_database_backups_path(database)
    expect(response).to have_http_status(:unauthorized)
  end
end

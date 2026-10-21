# frozen_string_literal: true

require "rails_helper"

# Backup writes authorize the database (DatabaseServicePolicy#update?), same as
# the dashboard — not its server (ServerPolicy#update?, system-admin only).
RSpec.describe "API::V1 backups authorization", type: :request do
  let(:database) { database_services(:one) }
  let(:member) { create(:user).tap { |u| create(:team_membership, user: u, team: app_records(:one).team, role: :member) } }
  let(:headers) { { "Authorization" => "Bearer #{api_v1_token_for(member)}" } }

  before { allow(BackupJob).to receive(:perform_later) }

  it "lets a team member (not a system admin) start a backup" do
    post "/api/v1/databases/#{database.id}/backups", headers: headers
    expect(response).to have_http_status(:created)
    expect(BackupJob).to have_received(:perform_later).with(database.id)
  end

  it "404s for another team's database" do
    post "/api/v1/databases/#{database_services(:two).id}/backups", headers: headers
    expect(response).to have_http_status(:not_found)
    expect(BackupJob).not_to have_received(:perform_later)
  end

  it "lets a team member restore" do
    destination = database.server.create_backup_destination!(enabled: true, provider: "r2", bucket: "b", access_key_id: "AK", secret_access_key: "SK")
    backup = database.backups.create!(backup_destination: destination, status: "completed", s3_key: "k/x.gz")
    allow(RestoreService).to receive(:new).and_return(instance_double(RestoreService, perform!: true))
    post "/api/v1/databases/#{database.id}/backups/#{backup.id}/restore", headers: headers
    expect(response).to have_http_status(:ok)
  end
end

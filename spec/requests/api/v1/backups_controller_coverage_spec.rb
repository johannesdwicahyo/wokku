# frozen_string_literal: true

require "rails_helper"

# Covers every action + guard/rescue branch of Api::V1::BackupsController.
# BackupJob is never enqueued for real; RestoreService and presigned-URL
# generation are stubbed so no SSH/S3 work happens.
RSpec.describe "API::V1::BackupsController", type: :request do
  # `create` authorizes ServerPolicy#update? which requires a *system* admin;
  # the single-admin validation pins that to the seeded admin@wokku.cloud
  # fixture, so reuse it rather than minting a second admin.
  let(:user) { users(:admin) }
  let!(:team) do
    t = Team.create!(name: "Backups Cov", owner: user)
    TeamMembership.create!(user: user, team: t, role: :admin)
    t
  end
  let(:server) { create(:server, team: team) }
  let(:db) { create(:database_service, server: server, service_type: "postgres", name: "covdb") }
  let(:headers) { api_v1_headers(user) }

  let!(:destination) do
    server.create_backup_destination!(enabled: true, provider: "r2", bucket: "b",
                                      access_key_id: "AK", secret_access_key: "SK")
  end

  def make_backup(status: "completed")
    db.backups.create!(backup_destination: destination, status: status, s3_key: "k/x.gz")
  end

  describe "GET index" do
    it "returns backups newest-first with the projected fields" do
      old = make_backup
      old.update_column(:created_at, 2.days.ago)
      fresh = make_backup

      get api_v1_database_backups_path(db), headers: headers
      expect(response).to have_http_status(:success)
      body = JSON.parse(response.body)
      expect(body.map { |b| b["id"] }).to eq([ fresh.id, old.id ])
      expect(body.first.keys).to match_array(%w[id status size_bytes created_at])
    end
  end

  describe "POST create" do
    it "enqueues a BackupJob and returns 201 on success" do
      expect {
        post api_v1_database_backups_path(db), headers: headers
      }.to have_enqueued_job(BackupJob).with(db.id)
      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["message"]).to eq("Backup started")
    end

    it "returns 402 and does not enqueue when the free-tier limit is reached" do
      allow_any_instance_of(DatabaseService).to receive(:backup_limit_reached?).and_return(true)

      expect {
        post api_v1_database_backups_path(db), headers: headers
      }.not_to have_enqueued_job(BackupJob)
      expect(response).to have_http_status(:payment_required)
      expect(JSON.parse(response.body)["error"]).to match(/Free tier limit reached/)
    end

    it "returns 422 with the error message when something blows up" do
      allow(DatabaseService).to receive(:lookup!).and_raise(StandardError, "kaboom")

      post api_v1_database_backups_path(db), headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to eq("kaboom")
    end
  end

  describe "GET download" do
    it "returns a presigned url and expiry" do
      backup = make_backup
      allow_any_instance_of(Backup).to receive(:download_url)
        .with(expires_in: 300).and_return("https://signed.example/x.gz")

      get download_api_v1_database_backup_path(db, backup), headers: headers
      expect(response).to have_http_status(:success)
      body = JSON.parse(response.body)
      expect(body).to eq("url" => "https://signed.example/x.gz", "expires_in" => 300)
    end

    it "404s for a missing backup id" do
      get download_api_v1_database_backup_path(db, "00000000-0000-0000-0000-000000000000"),
          headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST restore" do
    it "runs RestoreService and returns the restore summary" do
      backup = make_backup
      fake = instance_double("RestoreService", perform!: true)
      allow(RestoreService).to receive(:new).with(an_instance_of(Backup)).and_return(fake)

      post restore_api_v1_database_backup_path(db, backup), headers: headers
      expect(response).to have_http_status(:success)
      body = JSON.parse(response.body)
      expect(body["message"]).to eq("Restore completed")
      expect(body["restored_to"]).to eq("covdb")
      expect(body["from_backup"]).to eq(backup.id)
    end

    it "returns 422 when RestoreService raises" do
      backup = make_backup
      allow(RestoreService).to receive(:new).and_raise(StandardError, "restore failed")

      post restore_api_v1_database_backup_path(db, backup), headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body["error_code"]).to eq("restore_failed")
      expect(body["error"]).not_to include("restore failed:")
    end
  end

  describe "auth" do
    it "rejects index without a token" do
      get api_v1_database_backups_path(db)
      expect(response).to have_http_status(:unauthorized)
    end
  end
end

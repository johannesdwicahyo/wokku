# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::Backups", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  let(:user) { users(:two) }
  let(:database) { database_services(:two) }

  describe "GET index" do
    it "redirects to login when not authenticated" do
      get "/dashboard/addons/#{database.id}/backups"
      expect(response).to have_http_status(:redirect)
    end

    it "shows backups for an authenticated admin" do
      sign_in user
      get "/dashboard/addons/#{database.id}/backups"
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST create" do
    it "redirects when not authenticated" do
      post "/dashboard/addons/#{database.id}/backups"
      expect(response).to have_http_status(:redirect)
    end

    it "enqueues the backup job and redirects" do
      sign_in user
      post "/dashboard/addons/#{database.id}/backups"
      expect(response).to redirect_to("/dashboard/addons/#{database.id}/backups")
    end
  end

  describe "limit, download and restore" do
    before { sign_in user }

    it "blocks create when the free-tier backup limit is reached" do
      allow_any_instance_of(DatabaseService).to receive(:backup_limit_reached?).and_return(true)
      post "/dashboard/addons/#{database.id}/backups"
      expect(response).to redirect_to("/dashboard/addons/#{database.id}/backups")
      expect(flash[:alert]).to match(/limit reached/)
    end

    it "download redirects to the presigned URL" do
      backup = create(:backup, database_service: database)
      allow_any_instance_of(Backup).to receive(:download_url)
        .with(expires_in: 300).and_return("https://r2.example/get")
      get "/dashboard/addons/#{database.id}/backups/#{backup.id}/download"
      expect(response).to redirect_to("https://r2.example/get")
    end

    it "restore runs the RestoreService and reports success" do
      backup = create(:backup, database_service: database)
      restorer = instance_double(RestoreService)
      allow(RestoreService).to receive(:new).with(backup).and_return(restorer)
      expect(restorer).to receive(:perform!)
      post "/dashboard/addons/#{database.id}/backups/#{backup.id}/restore"
      expect(response).to redirect_to("/dashboard/addons/#{database.id}/backups")
      expect(flash[:notice]).to eq("Restore completed")
    end

    it "restore surfaces a failure as an alert" do
      backup = create(:backup, database_service: database)
      restorer = instance_double(RestoreService)
      allow(RestoreService).to receive(:new).and_return(restorer)
      allow(restorer).to receive(:perform!).and_raise(StandardError, "op timed out")
      post "/dashboard/addons/#{database.id}/backups/#{backup.id}/restore"
      expect(flash[:alert]).to eq("Restore failed: op timed out")
    end
  end
end

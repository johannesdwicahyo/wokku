# frozen_string_literal: true

require "rails_helper"

# Live coverage for Dashboard::BackupDestinationsController. Despite the
# Dashboard:: namespace, the only mounted route lives under the /admin
# namespace: /admin/servers/:server_id/backup_destination (edit/update). That
# /admin block is Devise-gated to admins, and the controller additionally calls
# `authorize @server, :update?` (admin-only). Admin fixture already has
# otp_required_for_login: true so it clears enforce_admin_2fa!.
#
# The pre-existing backup_destinations_controller_spec.rb is fully skipped
# (it targets the dead /dashboard/servers/* route); this file exercises the
# real route to drive the controller to coverage.
RSpec.describe "Dashboard::BackupDestinations (admin route)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { users(:admin) }
  let(:server) { servers(:one) }

  before do
    # Admin needs membership for enforce_admin_2fa! / current_team helpers
    # rendered in the admin layout.
    TeamMembership.find_or_create_by!(user: admin, team: teams(:one)) { |m| m.role = :admin }
  end

  describe "auth guards" do
    it "redirects an anonymous visitor on edit" do
      get edit_admin_server_backup_destination_path(server)
      expect(response).to have_http_status(:redirect)
    end

    it "404s for a non-admin (Devise authenticate block)" do
      sign_in users(:one)
      get edit_admin_server_backup_destination_path(server)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET edit" do
    it "builds a new destination and renders the form when none exists" do
      sign_in admin
      get edit_admin_server_backup_destination_path(server)
      expect(response).to have_http_status(:success)
    end

    it "loads the existing destination when one is present" do
      server.create_backup_destination!(provider: "s3", bucket: "existing-bucket")
      sign_in admin
      get edit_admin_server_backup_destination_path(server)
      expect(response).to have_http_status(:success)
      expect(response.body).to include("existing-bucket")
    end

    it "404s for an unknown server id" do
      sign_in admin
      get edit_admin_server_backup_destination_path("00000000-0000-0000-0000-000000000000")
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH update" do
    it "creates and saves a new destination, then redirects to the server" do
      sign_in admin
      expect {
        patch admin_server_backup_destination_path(server), params: {
          backup_destination: {
            provider: "s3", bucket: "my-bucket", region: "us-east-1",
            access_key_id: "AKIA", secret_access_key: "secret",
            retention_days: 30, enabled: true
          }
        }
      }.to change { server.reload.backup_destination }.from(nil)

      expect(response).to redirect_to(admin_server_path(server))
      follow_redirect!
      expect(flash[:notice]).to match(/saved/i)
    end

    it "updates an existing destination in place" do
      server.create_backup_destination!(provider: "s3", bucket: "old-bucket")
      sign_in admin
      patch admin_server_backup_destination_path(server), params: {
        backup_destination: { provider: "r2", bucket: "new-bucket" }
      }
      expect(response).to redirect_to(admin_server_path(server))
      expect(server.reload.backup_destination.bucket).to eq("new-bucket")
    end

    it "re-renders edit with 422 when the destination is invalid (blank bucket)" do
      sign_in admin
      patch admin_server_backup_destination_path(server), params: {
        backup_destination: { provider: "s3", bucket: "" }
      }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(server.reload.backup_destination).to be_nil
    end
  end
end

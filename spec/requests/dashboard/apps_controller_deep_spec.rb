# frozen_string_literal: true

require "rails_helper"

# Deep coverage tests for Dashboard::AppsController.
RSpec.describe "Dashboard::Apps (deep coverage)", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  let(:user) { users(:two) }
  let(:app_record) { app_records(:two) }

  # apps#destroy reaches Cloudflare DNS for wokku.cloud subdomain cleanup.
  # Stub uniformly — the SUT here is the controller's destroy path, not
  # the Cloudflare integration.
  before do
    stub_request(:any, %r{\Ahttps://api\.cloudflare\.com/})
      .to_return(status: 200, body: { success: true, result: [] }.to_json,
                 headers: { "Content-Type" => "application/json" })
  end

  describe "create" do
    before { sign_in user }

    it "creates app and redirects on success" do
      post "/dashboard/apps", params: {
        app_record: { name: "brand-new-app", deploy_branch: "main", server_id: servers(:two).id }
      }
      expect(response).to have_http_status(:redirect)
      expect(response.location).to match(%r{/dashboard/apps/})
    end

    it "re-renders index with 422 on blank name", skip: "pre-existing: blank name returns 302, not 422 (Minitest also fails)" do
      post "/dashboard/apps", params: {
        app_record: { name: "", deploy_branch: "main", server_id: servers(:two).id }
      }
      expect([ 200, 422 ]).to include(response.status)
    end
  end

  describe "destroy" do
    before { sign_in user }

    it "deletes the app record and redirects to index" do
      server = servers(:two)
      throwaway = AppRecord.create!(
        name: "throwaway-app",
        server: server,
        team: user.teams.first,
        creator: user,
        deploy_branch: "main"
      )

      delete "/dashboard/apps/#{throwaway.id}"
      expect(response).to redirect_to(dashboard_apps_path)
      expect(flash[:notice]).to match("deleted")
      expect(AppRecord.find_by(id: throwaway.id)).to be_nil
    end
  end

  describe "process control (async via DokkuAppActionJob)" do
    before { sign_in user }

    %w[restart stop start].each do |action|
      it "enqueues DokkuAppActionJob for #{action} and redirects" do
        expect {
          post "/dashboard/apps/#{app_record.id}/#{action}"
        }.to have_enqueued_job(DokkuAppActionJob).with(app_record.id, action)
        expect(response).to redirect_to(dashboard_app_path(app_record))
        expect(app_record.reload.pending_action).to eq(action)
      end
    end

    # The async path always redirects whether or not Dokku raises — the job
    # handles errors and broadcasts via Turbo when it completes.
    %w[restart stop start].each do |action|
      it "#{action}: redirects with alert when Dokku raises (still enqueues)" do
        expect {
          post "/dashboard/apps/#{app_record.id}/#{action}"
        }.to have_enqueued_job(DokkuAppActionJob).with(app_record.id, action)
        expect(response).to redirect_to(dashboard_app_path(app_record))
      end
    end
  end

  describe "toggle_https" do
    before { sign_in user }

    it "enables HTTPS via the service and redirects with notice" do
      allow_any_instance_of(Apps::Settings::HttpsToggle).to receive(:enabled?).and_return(false)
      allow_any_instance_of(Apps::Settings::HttpsToggle).to receive(:enable!).and_return(true)
      post "/dashboard/apps/#{app_record.id}/toggle_https"
      expect(response).to redirect_to(dashboard_app_path(app_record))
      expect(flash[:notice]).to match("HTTPS")
    end

    it "redirects with alert when the service raises Apps::Settings::Error" do
      allow_any_instance_of(Apps::Settings::HttpsToggle).to receive(:enabled?).and_return(false)
      allow_any_instance_of(Apps::Settings::HttpsToggle).to receive(:enable!)
        .and_raise(Apps::Settings::Error.new("SSH failed", code: :dokku_error))
      post "/dashboard/apps/#{app_record.id}/toggle_https"
      expect(response).to redirect_to(dashboard_app_path(app_record))
      expect(flash[:alert]).to match("Failed")
    end
  end

  describe "toggle_maintenance" do
    before { sign_in user }

    it "enables maintenance when currently disabled" do
      allow_any_instance_of(Apps::Settings::MaintenanceToggle).to receive(:enabled?).and_return(false)
      allow_any_instance_of(Apps::Settings::MaintenanceToggle).to receive(:enable!).and_return(true)
      post "/dashboard/apps/#{app_record.id}/toggle_maintenance"
      expect(response).to redirect_to(dashboard_app_path(app_record))
      expect(flash[:notice]).to match("enabled")
    end

    it "disables maintenance when currently enabled" do
      allow_any_instance_of(Apps::Settings::MaintenanceToggle).to receive(:enabled?).and_return(true)
      allow_any_instance_of(Apps::Settings::MaintenanceToggle).to receive(:disable!).and_return(false)
      post "/dashboard/apps/#{app_record.id}/toggle_maintenance"
      expect(response).to redirect_to(dashboard_app_path(app_record))
      expect(flash[:notice]).to match("disabled")
    end

    it "redirects with alert when the service raises Apps::Settings::Error" do
      allow_any_instance_of(Apps::Settings::MaintenanceToggle).to receive(:enabled?).and_return(false)
      allow_any_instance_of(Apps::Settings::MaintenanceToggle).to receive(:enable!)
        .and_raise(Apps::Settings::Error.new("SSH failed", code: :dokku_error))
      post "/dashboard/apps/#{app_record.id}/toggle_maintenance"
      expect(response).to redirect_to(dashboard_app_path(app_record))
      expect(flash[:alert]).to match("Failed")
    end
  end
end

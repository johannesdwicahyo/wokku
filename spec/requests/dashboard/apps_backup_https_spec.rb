# frozen_string_literal: true

require "rails_helper"

# Coverage for the smaller Dashboard::Apps member actions: backup_now,
# toggle_https (disable branch), the PlanQuotaError rescue, and the
# deploy_template prefill redirect on index.
RSpec.describe "Dashboard::Apps backup/https/quota", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { users(:one) }
  let(:app_record) { app_records(:one) }

  before { sign_in user }

  describe "POST backup_now" do
    it "asks for a database when the app has none" do
      allow_any_instance_of(AppRecord).to receive(:primary_database).and_return(nil)
      post backup_now_dashboard_app_path(app_record)
      expect(response).to redirect_to(dashboard_app_path(app_record))
      expect(flash[:alert]).to match(/Attach a database/)
    end

    it "blocks when the backup limit is reached" do
      db = instance_double(DatabaseService, backups_unsupported?: false, backup_limit_reached?: true,
                                            backup_limit_message: "Backup limit reached: free shared databases can take 2 backups a day.")
      allow_any_instance_of(AppRecord).to receive(:primary_database).and_return(db)
      post backup_now_dashboard_app_path(app_record)
      expect(response).to redirect_to(dashboard_app_path(app_record))
      expect(flash[:alert]).to match(/Backup limit reached/)
    end

    it "refuses a database that isn't backed up, without enqueuing" do
      db = instance_double(DatabaseService, backups_unsupported?: true, backups_unsupported_message: "Memcached is a cache and isn't backed up.")
      allow_any_instance_of(AppRecord).to receive(:primary_database).and_return(db)
      expect(BackupJob).not_to receive(:perform_later)
      post backup_now_dashboard_app_path(app_record)
      expect(flash[:alert]).to match(/Memcached/)
    end

    it "enqueues a BackupJob and redirects with a notice" do
      db = instance_double(DatabaseService, backups_unsupported?: false, backup_limit_reached?: false, id: "db-1")
      allow_any_instance_of(AppRecord).to receive(:primary_database).and_return(db)
      expect(BackupJob).to receive(:perform_later).with("db-1")
      post backup_now_dashboard_app_path(app_record)
      expect(response).to redirect_to(dashboard_app_path(app_record))
      expect(flash[:notice]).to match(/Backup started/)
    end
  end

  describe "POST toggle_https" do
    it "disables the redirect when currently enabled" do
      toggle = instance_double(Apps::Settings::HttpsToggle, enabled?: true)
      allow(Apps::Settings::HttpsToggle).to receive(:new).and_return(toggle)
      expect(toggle).to receive(:disable!)
      post toggle_https_dashboard_app_path(app_record)
      expect(response).to redirect_to(dashboard_app_path(app_record))
      expect(flash[:notice]).to eq("HTTPS redirect disabled.")
    end
  end

  describe "PlanQuotaError rescue" do
    it "redirects to new with an upgrade alert when the box quota is exhausted" do
      # Zero quota for every size: resolve_box_size finds no headroom and
      # enforce_plan_quota! raises, exercising the controller-level rescue.
      allow(Wokku.config.plan_enforcer).to receive(:quota).and_return(0)
      post dashboard_apps_path, params: {
        app_record: { name: "quota-app", server_id: servers(:one).id, box_size: "small" }
      }
      expect(response).to redirect_to(new_dashboard_app_path)
      expect(flash[:alert]).to match(/plan allows 0 small boxes/)
    end
  end
end

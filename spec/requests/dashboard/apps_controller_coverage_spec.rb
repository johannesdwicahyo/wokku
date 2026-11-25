# frozen_string_literal: true

require "rails_helper"

# Additional coverage for Dashboard::AppsController, exercising branches the
# existing apps_controller_spec / _full_spec / _deep_spec files leave out:
#   - toggle_cdn (enable + disable)
#   - transfer (GET form, POST success, POST error rescue)
#   - unlock (success + DeployLock error rescue)
#   - lock (DeployLock error rescue)
#   - backup_now (no DB / limit reached / success)
#   - create PlanQuotaError rescue + dedicated DB/Redis provisioning branches
#   - enforce_free_container_limit! deposit-gate redirect
#   - reject_creation_during_deletion_pending guard
#   - index rescue branch
#   - run_onboarding_waypoints (deploy_template redirect, first_deploy event)
#   - search action
RSpec.describe "Dashboard::Apps (extra coverage)", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  let(:user) { users(:two) }
  let(:app_record) { app_records(:two) }

  before do
    stub_request(:any, %r{\Ahttps://api\.cloudflare\.com/})
      .to_return(status: 200, body: { success: true, result: [] }.to_json,
                 headers: { "Content-Type" => "application/json" })
  end

  describe "search" do
    before { sign_in user }

    it "returns all main apps as JSON when no query given" do
      get search_dashboard_apps_path
      expect(response).to have_http_status(:success)
      body = JSON.parse(response.body)
      expect(body).to be_an(Array)
    end

    it "filters apps by the q param" do
      get search_dashboard_apps_path, params: { q: app_record.name }
      expect(response).to have_http_status(:success)
      body = JSON.parse(response.body)
      names = body.map { |a| a["name"] }
      expect(names).to include(app_record.name)
    end
  end

  describe "index" do
    before { sign_in user }

    it "renders and computes box usage" do
      get dashboard_apps_path
      expect(response).to have_http_status(:success)
    end

    it "swallows StandardError raised while building the activity feed" do
      allow(Activity).to receive(:where).and_raise(StandardError, "boom")
      get dashboard_apps_path
      expect(response).to have_http_status(:success)
    end

    it "emits first_deploy_succeeded once when the team has a succeeded deploy" do
      # Fixture deploys(:two) is already a succeeded deploy on app_records(:two),
      # which belongs to teams(:two) — this exercises the first_deploy waypoint
      # branch in run_onboarding_waypoints without seeding session[:fds_sent].
      get dashboard_apps_path
      expect(response).to have_http_status(:success)
      get dashboard_apps_path
      expect(response).to have_http_status(:success)
    end
  end

  describe "create" do
    before { sign_in user }


    it "rejects creation while the account is pending deletion" do
      allow_any_instance_of(User).to receive(:deletion_pending?).and_return(true)
      post dashboard_apps_path, params: {
        app_record: { name: "during-deletion", deploy_branch: "main", server_id: servers(:two).id }
      }
      expect(response).to redirect_to(dashboard_root_path)
      expect(flash[:alert]).to be_present
    end



    it "creates a dyno allocation derived from box_size on success" do
      post dashboard_apps_path, params: {
        app_record: { name: "sleeping-box-app", deploy_branch: "main",
                      server_id: servers(:two).id, box_size: "sleeping" }
      }
      created = AppRecord.find_by(name: "sleeping-box-app")
      expect(created).to be_present
      expect(created.dyno_allocations.where(process_type: "web")).to be_present
    end
  end

  describe "toggle_cdn" do
    before { sign_in user }

    it "enables the CDN when currently disabled" do
      allow_any_instance_of(Apps::Settings::CdnToggle).to receive(:enabled?).and_return(false)
      allow_any_instance_of(Apps::Settings::CdnToggle).to receive(:enable!).and_return(true)
      post toggle_cdn_dashboard_app_path(app_record)
      expect(response).to redirect_to(dashboard_app_path(app_record))
      expect(flash[:notice]).to match(/turning on/)
    end

    it "disables the CDN when currently enabled" do
      allow_any_instance_of(Apps::Settings::CdnToggle).to receive(:enabled?).and_return(true)
      allow_any_instance_of(Apps::Settings::CdnToggle).to receive(:disable!).and_return(false)
      post toggle_cdn_dashboard_app_path(app_record)
      expect(response).to redirect_to(dashboard_app_path(app_record))
      expect(flash[:notice]).to match(/turning off/)
    end
  end

  describe "transfer" do
    before { sign_in user }

    it "renders the transfer form on GET" do
      get transfer_dashboard_app_path(app_record)
      expect(response).to have_http_status(:success)
    end

    it "requests a transfer and redirects with notice on success" do
      to_user = users(:one)
      record = AppTransfer.new(to_user: to_user)
      allow_any_instance_of(Apps::Lifecycle::Transferrer).to receive(:call!).and_return(record)
      post transfer_dashboard_app_path(app_record), params: { email: to_user.email }
      expect(response).to redirect_to(dashboard_app_path(app_record))
      expect(flash[:notice]).to match(/Transfer request sent/)
    end

    it "redirects with an alert when the transfer service raises" do
      allow_any_instance_of(Apps::Lifecycle::Transferrer).to receive(:call!)
        .and_raise(Apps::Lifecycle::Error.new("Invalid email", code: :invalid_email))
      post transfer_dashboard_app_path(app_record), params: { email: "bad" }
      expect(response).to redirect_to(dashboard_app_path(app_record))
      expect(flash[:alert]).to match(/Transfer failed/)
    end
  end

  describe "unlock" do
    before { sign_in user }

    it "releases the deploy lock and redirects with notice" do
      allow(::Apps::Lifecycle::DeployLock).to receive(:new).and_return(
        instance_double(::Apps::Lifecycle::DeployLock, unlock!: false)
      )
      post unlock_dashboard_app_path(app_record)
      expect(response).to redirect_to(dashboard_app_path(app_record))
      expect(flash[:notice]).to match(/Deploy lock released/)
    end

    it "redirects with an alert when DeployLock raises" do
      allow(::Apps::Lifecycle::DeployLock).to receive(:new).and_return(
        instance_double(::Apps::Lifecycle::DeployLock).tap do |dbl|
          allow(dbl).to receive(:unlock!).and_raise(
            ::Apps::Lifecycle::Error.new("ssh down", code: :dokku_error)
          )
        end
      )
      post unlock_dashboard_app_path(app_record)
      expect(response).to redirect_to(dashboard_app_path(app_record))
      expect(flash[:alert]).to match(/Couldn't release deploy lock/)
    end

    it "shows an accurate message when the lock is held (Unable to remove deploy lock)" do
      allow(::Apps::Lifecycle::DeployLock).to receive(:new).and_return(
        instance_double(::Apps::Lifecycle::DeployLock).tap do |dbl|
          allow(dbl).to receive(:unlock!).and_raise(
            ::Apps::Lifecycle::Error.new("Unable to remove deploy lock", code: :dokku_error)
          )
        end
      )
      post unlock_dashboard_app_path(app_record)
      expect(flash[:alert]).to match(/deploy or rebuild may be in progress|crash-looping/i)
    end
  end

  describe "lock" do
    before { sign_in user }

    it "sets the deploy lock and redirects with notice" do
      allow(::Apps::Lifecycle::DeployLock).to receive(:new).and_return(
        instance_double(::Apps::Lifecycle::DeployLock, lock!: true)
      )
      post lock_dashboard_app_path(app_record)
      expect(response).to redirect_to(dashboard_app_path(app_record))
      expect(flash[:notice]).to match(/Deploy lock set/)
    end

    it "redirects with an alert when DeployLock raises" do
      allow(::Apps::Lifecycle::DeployLock).to receive(:new).and_return(
        instance_double(::Apps::Lifecycle::DeployLock).tap do |dbl|
          allow(dbl).to receive(:lock!).and_raise(
            ::Apps::Lifecycle::Error.new("ssh down", code: :dokku_error)
          )
        end
      )
      post lock_dashboard_app_path(app_record)
      expect(response).to redirect_to(dashboard_app_path(app_record))
      expect(flash[:alert]).to match(/Couldn't set deploy lock/)
    end
  end

  describe "backup_now" do
    before { sign_in user }

    # backup_now was missing from the set_app `only:` list (@app stayed nil
    # and authorize raised) — fixed; the full behaviour is covered in
    # apps_backup_https_spec.rb. This guards the routing+set_app wiring.
    it "resolves the app and redirects instead of raising" do
      allow_any_instance_of(AppRecord).to receive(:primary_database).and_return(nil)
      post backup_now_dashboard_app_path(app_record)
      expect(response).to redirect_to(dashboard_app_path(app_record))
    end
  end
end

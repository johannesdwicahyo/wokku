# frozen_string_literal: true

require "rails_helper"

# Named :system per the plan but runs as a request spec (rack_test, no JS)
# to exercise the full controller + view stack end-to-end.
#
# The "settings" tab in the app UI maps to /dashboard/apps/:app_id/domains
# (the DomainsController#index action), which renders AppSettingsComponent.
# AppSettingsComponent always renders the shared-addon section, so the
# "Upgrade to dedicated" button appears there for running shared tenants.
#
# Coverage:
#   1. GET /dashboard/apps/:id/domains — shared addon card renders with
#      "Upgrade to dedicated" button for a running shared Postgres tenant.
#   2. POST upgrade_to_dedicated (happy path) — redirects to settings tab with
#      a notice.
#   3. After upgrade, shared tenant is pending_destroy — card shows cleanup
#      copy instead of Upgrade button.
#   4. POST upgrade_to_dedicated (pre-flight failure) — redirects back with
#      the UpgradeError::NoFreeSlots alert message.
RSpec.describe "Upgrade shared Postgres to dedicated", type: :request do
  include Devise::Test::IntegrationHelpers
  include Rails.application.routes.url_helpers

  around do |ex|
    orig = ENV["BUNDLE_V2_ENABLED"]
    ENV["BUNDLE_V2_ENABLED"] = "true"
    ex.run
  ensure
    ENV["BUNDLE_V2_ENABLED"] = orig
  end

  # users(:one) is a regular member (non-admin, no 2FA redirect) with
  # team membership in teams(:one). app_records(:one) belongs to teams(:one).
  let(:user)       { users(:one) }
  let(:app_record) { app_records(:one) }
  let(:server)     { servers(:one) }

  # Build the shared-Postgres row the card renders from.
  # Shared tenants require a parent "shared host" DatabaseService.
  let!(:shared_host) do
    DatabaseService.create!(
      server: server,
      name: "dokku-shared-postgres-smoke-#{SecureRandom.hex(4)}",
      service_type: "postgres",
      tier_name: "shared_host",
      shared: false,
      status: :running
    )
  end

  let!(:shared_tenant) do
    DatabaseService.create!(
      server: server,
      parent_service: shared_host,
      name: "shared-pg-smoke-#{SecureRandom.hex(4)}",
      service_type: "postgres",
      tier_name: DatabaseProvisioner::SHARED_TIER,
      shared: true,
      status: :running,
      creator: user,
      shared_role_name: "smoke_role",
      shared_db_name: "smoke_db",
      live_db_bytes: 10 * 1024 * 1024
    )
  end

  let!(:app_database) do
    AppDatabase.create!(
      app_record: app_record,
      database_service: shared_tenant,
      alias_name: "DATABASE"
    )
  end

  # The settings tab is served at the domains index route.
  let(:settings_url) { dashboard_app_domains_path(app_record) }
  let(:upgrade_url)  { "/dashboard/apps/#{app_record.id}/addons/postgres/upgrade" }

  before { sign_in user }

  # ── 1. Settings tab renders the "Upgrade to dedicated" button ─────────────

  describe "GET settings tab (domains page)" do
    it "renders the shared addon card with the Upgrade button for a running shared tenant" do
      get settings_url
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Upgrade to dedicated")
      expect(response.body).to include("SHARED")
    end
  end

  # ── 2. Happy path: upgrade kicks off, redirect with notice ────────────────

  describe "POST upgrade_to_dedicated (happy path)" do
    before do
      dedicated = instance_double(DatabaseService, id: SecureRandom.uuid)
      allow(DatabaseServiceUpgrade).to receive(:call)
        .with(app: app_record, user: user)
        .and_return(dedicated)
    end

    it "redirects to the settings tab with an upgrading notice" do
      post upgrade_url
      expect(response).to redirect_to(dashboard_app_domains_path(app_record))
      follow_redirect!
      expect(flash[:notice]).to match(/Upgrading/i)
    end
  end

  # ── 3. After upgrade: pending_destroy shows cleanup copy, no Upgrade button ──

  describe "GET settings tab when shared tenant is pending_destroy" do
    before { shared_tenant.update!(status: :pending_destroy) }

    it "shows the pending cleanup copy instead of the Upgrade button" do
      get settings_url
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("pending cleanup")
      expect(response.body).not_to include("Upgrade to dedicated")
    end
  end

  # ── 4. Pre-flight failure: NoFreeSlots redirects with alert ──────────────

  describe "POST upgrade_to_dedicated (pre-flight failure — no free slots)" do
    before do
      allow(DatabaseServiceUpgrade).to receive(:call)
        .and_raise(UpgradeError::NoFreeSlots)
    end

    it "redirects back to the settings tab with the error message in flash[:alert]" do
      post upgrade_url
      expect(response).to redirect_to(dashboard_app_domains_path(app_record))
      expect(flash[:alert]).to include("dedicated Postgres slots")
    end
  end
end

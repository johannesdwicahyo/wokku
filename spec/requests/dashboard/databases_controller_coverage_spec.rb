# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard::Databases coverage", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { create(:user, :with_personal_team) }
  let(:team) { user.teams.first }
  let(:server) { create(:server, team: team) }
  let(:target_app) { create(:app_record, team: team, server: server, creator: user) }
  let(:database) do
    create(:database_service, server: server, service_type: "postgres",
                              creator: user, tier_name: "basic", status: :running)
  end

  before do
    # W7 Phase 2: link/unlink/info are control-plane writes/reads — no SSH.
    # Converge (the dokku-restart equivalent) is stubbed as out of scope.
    allow(Apps::Restarter).to receive(:restart)
    sign_in user
  end

  # ---------------------------------------------------------------------------
  # show
  # ---------------------------------------------------------------------------
  describe "GET show" do
    it "renders the addon show page (happy path)" do
      target_app # ensure the app exists for the picker
      get "/dashboard/addons/#{database.id}"
      expect(response).to have_http_status(:success)
    end

    it "resolves the addon by name via lookup!" do
      get "/dashboard/addons/#{database.name}"
      expect(response).to have_http_status(:success)
    end

    it "renders the stored DSN as the connection info" do
      database.update!(dsn: "postgres://u:secret@dokku.postgres.db:5432/db")
      get "/dashboard/addons/#{database.id}"
      expect(response).to have_http_status(:success)
      expect(response.body).to include("postgres://u:secret@dokku.postgres.db:5432/db")
    end

    it "swallows a failing info fetch (e.g. undecryptable legacy DSN) and still renders" do
      allow_any_instance_of(DatabaseService).to receive(:dsn).and_raise(StandardError, "boom")
      get "/dashboard/addons/#{database.id}"
      expect(response).to have_http_status(:success)
    end

    it "skips usage metrics for a shared database" do
      parent = create(:database_service, server: server, service_type: "postgres", creator: user)
      shared = create(:database_service, server: server, service_type: "postgres",
                                         creator: user, shared: true, parent_service: parent)
      get "/dashboard/addons/#{shared.id}"
      expect(response).to have_http_status(:success)
    end

    it "exposes live usage metrics for a dedicated database" do
      database.update_columns(
        live_db_bytes: 1234,
        live_mem_used_mb: 64,
        live_metrics_at: 1.minute.ago
      )
      get "/dashboard/addons/#{database.id}"
      expect(response).to have_http_status(:success)
    end
  end

  # ---------------------------------------------------------------------------
  # settings
  # ---------------------------------------------------------------------------
  describe "GET settings" do
    it "renders the settings page" do
      get "/dashboard/addons/#{database.id}/settings"
      expect(response).to have_http_status(:success)
    end
  end

  # ---------------------------------------------------------------------------
  # new
  # ---------------------------------------------------------------------------
  describe "GET new" do
    it "redirects the stale standalone form to the addons index" do
      get "/dashboard/addons/new"
      expect(response).to redirect_to(dashboard_addons_path)
    end
  end

  # ---------------------------------------------------------------------------
  # create
  # ---------------------------------------------------------------------------
  describe "POST create" do
    it "queues CreateAddonJob and redirects to app resources (dedicated)" do
      expect do
        post "/dashboard/addons", params: {
          database_service: { name: "fresh-pg", service_type: "postgres", app_id: target_app.id }
        }
      end.to have_enqueued_job(CreateAddonJob)
      expect(response).to redirect_to(dashboard_app_resources_path(target_app))
    end

    it "defaults a blank tier_name to basic" do
      post "/dashboard/addons", params: {
        database_service: { name: "blank-tier-pg", service_type: "postgres", tier_name: "", app_id: target_app.id }
      }
      created = DatabaseService.find_by(name: "blank-tier-pg")
      expect(created.tier_name).to eq("basic")
    end

    it "sweeps stuck error/creating rows holding the name slot" do
      stuck = create(:database_service, server: server, name: "stuck-pg",
                                        creator: user, status: :error, service_type: "postgres")
      stuck.update_column(:created_at, 10.minutes.ago)
      post "/dashboard/addons", params: {
        database_service: { name: "stuck-pg", service_type: "postgres", app_id: target_app.id }
      }
      expect(DatabaseService.exists?(stuck.id)).to be(false)
    end

    it "redirects with an alert when no app is selected" do
      post "/dashboard/addons", params: {
        database_service: { name: "no-app-pg", service_type: "postgres" }
      }
      expect(response).to redirect_to(dashboard_addons_path)
      expect(flash[:alert]).to eq("Pick an app first.")
    end

    it "redirects with a validation alert when save fails" do
      post "/dashboard/addons", params: {
        database_service: { name: "", service_type: "postgres", app_id: target_app.id }
      }
      expect(response).to redirect_to(dashboard_addons_path)
      expect(flash[:alert]).to match(/Couldn't create add-on/)
    end

    describe "shared mode" do
      it "attaches a shared engine when provisioned" do
        provisioner = instance_double(Addons::SharedProvisioner, call: :provisioned)
        allow(Addons::SharedProvisioner).to receive(:new).and_return(provisioner)
        post "/dashboard/addons", params: {
          mode: "shared",
          database_service: { service_type: "postgres", app_id: target_app.id }
        }
        expect(response).to redirect_to(dashboard_app_resources_path(target_app))
        expect(flash[:notice]).to match(/attached/)
      end

      it "handles already_attached" do
        provisioner = instance_double(Addons::SharedProvisioner, call: :already_attached)
        allow(Addons::SharedProvisioner).to receive(:new).and_return(provisioner)
        post "/dashboard/addons", params: {
          mode: "shared",
          database_service: { service_type: "postgres", app_id: target_app.id }
        }
        expect(flash[:notice]).to match(/already attached/)
      end

      it "handles feature_disabled" do
        provisioner = instance_double(Addons::SharedProvisioner, call: :feature_disabled)
        allow(Addons::SharedProvisioner).to receive(:new).and_return(provisioner)
        post "/dashboard/addons", params: {
          mode: "shared",
          database_service: { service_type: "postgres", app_id: target_app.id }
        }
        expect(response).to redirect_to(dashboard_addons_path)
        expect(flash[:alert]).to match(/not enabled/)
      end

      it "handles an unexpected provisioner result" do
        provisioner = instance_double(Addons::SharedProvisioner, call: :something_else)
        allow(Addons::SharedProvisioner).to receive(:new).and_return(provisioner)
        post "/dashboard/addons", params: {
          mode: "shared",
          database_service: { service_type: "postgres", app_id: target_app.id }
        }
        expect(response).to redirect_to(dashboard_addons_path)
        expect(flash[:alert]).to match(/Couldn't attach/)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # destroy
  # ---------------------------------------------------------------------------
  describe "DELETE destroy" do
    it "routes through DatabaseProvisioner.destroy! (service.destroy op — no raw dokku), destroys the service, and redirects" do
      database.update!(wokkud_managed: true)
      create(:app_database, app_record: target_app, database_service: database)
      allow(Services::Ops).to receive(:issue_and_wait!)
      expect(DatabaseProvisioner).to receive(:destroy!).with(database_service: database).and_call_original
      delete "/dashboard/addons/#{database.id}"
      expect(Services::Ops).to have_received(:issue_and_wait!)
        .with(service: database, kind: "service.destroy", params: { force: true })
      expect(DatabaseService.exists?(database.id)).to be(false)
      expect(response).to redirect_to(dashboard_addons_path)
      expect(flash[:notice]).to match(/destroyed/)
    end

    it "cascades the AppDatabase link when the service is destroyed (no separate unlink step)" do
      database.update!(wokkud_managed: true)
      allow(Services::Ops).to receive(:issue_and_wait!)
      app_database = create(:app_database, app_record: target_app, database_service: database)
      delete "/dashboard/addons/#{database.id}"
      expect(AppDatabase.exists?(app_database.id)).to be(false)
      expect(DatabaseService.exists?(database.id)).to be(false)
    end

    it "rescues an unexpected error and redirects with an alert" do
      allow(DatabaseProvisioner).to receive(:destroy!).and_raise(StandardError, "ssh down")
      delete "/dashboard/addons/#{database.id}"
      expect(response).to redirect_to(dashboard_addons_path)
      expect(flash[:alert]).to match(/Failed to destroy/)
    end
  end

  it "never references Dokku:: in the destroy action" do
    source = File.read(Wokku::Engine.root.join("app/controllers/dashboard/databases_controller.rb"))
    destroy_body = source[/def destroy\n(.*?)\n    end/m, 1]
    expect(destroy_body).not_to match(/Dokku::/)
  end

  # ---------------------------------------------------------------------------
  # retry
  # ---------------------------------------------------------------------------
  describe "POST retry" do
    it "re-enqueues CreateAddonJob using a linked app" do
      create(:app_database, app_record: target_app, database_service: database)
      database.update!(status: :error)
      expect do
        post "/dashboard/addons/#{database.id}/retry"
      end.to have_enqueued_job(CreateAddonJob)
      expect(response).to redirect_to(dashboard_addon_path(database))
      expect(database.reload.status).to eq("creating")
    end

    it "falls back to the creator's first app when unlinked" do
      target_app # creator has an app, no link to the db
      database.update!(status: :error)
      expect do
        post "/dashboard/addons/#{database.id}/retry"
      end.to have_enqueued_job(CreateAddonJob)
    end

    it "redirects with an alert when no app can be found" do
      orphan = create(:database_service, server: server, creator: user, status: :error)
      post "/dashboard/addons/#{orphan.id}/retry"
      expect(response).to redirect_to(dashboard_addon_path(orphan))
      expect(flash[:alert]).to match(/Pick an app/)
    end
  end

  # ---------------------------------------------------------------------------
  # change_tier
  # ---------------------------------------------------------------------------
  describe "POST change_tier" do
    let!(:tier) do
      ServiceTier.find_or_create_by!(service_type: "postgres", name: "standard") do |t|
        t.monthly_price_cents = 1000
        t.price_cents_per_hour = 2
        t.available = true
      end
    end

    it "updates the tier and queues ApplyDatabaseTierJob" do
      expect do
        post "/dashboard/addons/#{database.id}/change_tier", params: { tier_name: "standard" }
      end.to have_enqueued_job(ApplyDatabaseTierJob)
      expect(database.reload.tier_name).to eq("standard")
      expect(flash[:notice]).to match(/Tier change/)
    end

    it "refuses to change tier on a shared database" do
      parent = create(:database_service, server: server, service_type: "postgres", creator: user)
      shared = create(:database_service, server: server, service_type: "postgres",
                                         creator: user, shared: true, parent_service: parent)
      post "/dashboard/addons/#{shared.id}/change_tier", params: { tier_name: "standard" }
      expect(response).to redirect_to(dashboard_addon_path(shared))
      expect(flash[:alert]).to match(/can't change tier/)
    end

    it "alerts when the tier doesn't exist" do
      post "/dashboard/addons/#{database.id}/change_tier", params: { tier_name: "nonexistent" }
      expect(response).to redirect_to(dashboard_addon_path(database))
      expect(flash[:alert]).to eq("Tier not available.")
    end

    it "rescues an unexpected error" do
      allow(ApplyDatabaseTierJob).to receive(:perform_later).and_raise(StandardError, "kaboom")
      post "/dashboard/addons/#{database.id}/change_tier", params: { tier_name: "standard" }
      expect(flash[:alert]).to match(/Tier change failed/)
    end
  end

  # ---------------------------------------------------------------------------
  # link
  # ---------------------------------------------------------------------------
  describe "POST link" do
    it "creates the AppDatabase row, writes the alias'd env var, and converges" do
      database.update!(dsn: "postgres://u:s@dokku.postgres.db:5432/db")
      post "/dashboard/addons/#{database.id}/link", params: { app_id: target_app.id }

      link = database.app_databases.find_by(app_record: target_app)
      expect(link.alias_name).to eq("POSTGRES")
      expect(target_app.env_vars.find_by(key: "POSTGRES_URL").value)
        .to eq("postgres://u:s@dokku.postgres.db:5432/db")
      expect(Apps::Restarter).to have_received(:restart).with(target_app)
      expect(flash[:notice]).to match(/Linked/)
    end

    it "uses the DATABASE alias for shared tenants (DATABASE_URL, never POSTGRES_URL)" do
      parent = create(:database_service, server: server, service_type: "postgres", creator: user)
      shared = create(:database_service, server: server, service_type: "postgres",
                                         creator: user, shared: true, parent_service: parent,
                                         dsn: "postgres://t:s@dokku-shared-postgres:5432/t")
      post "/dashboard/addons/#{shared.id}/link", params: { app_id: target_app.id }

      expect(shared.app_databases.find_by(app_record: target_app).alias_name).to eq("DATABASE")
      expect(target_app.env_vars.find_by(key: "DATABASE_URL")).to be_present
    end

    it "is idempotent — relinking an already-linked app keeps the row and succeeds" do
      create(:app_database, app_record: target_app, database_service: database, alias_name: "POSTGRES")
      expect {
        post "/dashboard/addons/#{database.id}/link", params: { app_id: target_app.id }
      }.not_to change { AppDatabase.count }
      expect(flash[:notice]).to match(/Linked/)
    end

    it "skips the env write when the row has no stored DSN" do
      post "/dashboard/addons/#{database.id}/link", params: { app_id: target_app.id }
      expect(target_app.env_vars.find_by(key: "POSTGRES_URL")).to be_nil
      expect(flash[:notice]).to match(/Linked/)
    end

    it "rescues an unexpected link error" do
      allow(Apps::EnvWriter).to receive(:set).and_raise(StandardError, "explode")
      database.update!(dsn: "postgres://u:s@h:5432/d")
      post "/dashboard/addons/#{database.id}/link", params: { app_id: target_app.id }
      expect(response).to redirect_to(dashboard_addon_path(database))
      expect(flash[:alert]).to match(/Link failed/)
    end

    it "swallows a converge failure — the link itself is committed" do
      allow(Apps::Restarter).to receive(:restart).and_raise(StandardError, "converge boom")
      post "/dashboard/addons/#{database.id}/link", params: { app_id: target_app.id }
      expect(database.app_databases.find_by(app_record: target_app)).to be_present
      expect(flash[:notice]).to match(/Linked/)
    end
  end

  # ---------------------------------------------------------------------------
  # unlink
  # ---------------------------------------------------------------------------
  describe "POST unlink" do
    it "removes the AppDatabase row, unsets the alias'd env var, and converges" do
      create(:app_database, app_record: target_app, database_service: database, alias_name: "POSTGRES")
      target_app.env_vars.create!(key: "POSTGRES_URL", value: "postgres://u:s@h:5432/d")

      post "/dashboard/addons/#{database.id}/unlink", params: { app_id: target_app.id }

      expect(database.app_databases.find_by(app_record: target_app)).to be_nil
      expect(target_app.env_vars.find_by(key: "POSTGRES_URL")).to be_nil
      expect(Apps::Restarter).to have_received(:restart).with(target_app)
      expect(flash[:notice]).to match(/Unlinked/)
    end

    it "unsets by the row's stored alias, not the service type" do
      create(:app_database, app_record: target_app, database_service: database, alias_name: "DATABASE")
      target_app.env_vars.create!(key: "DATABASE_URL", value: "postgres://u:s@h:5432/d")

      post "/dashboard/addons/#{database.id}/unlink", params: { app_id: target_app.id }

      expect(target_app.env_vars.find_by(key: "DATABASE_URL")).to be_nil
    end

    it "rescues an unexpected unlink error" do
      create(:app_database, app_record: target_app, database_service: database)
      allow(Apps::EnvWriter).to receive(:unset).and_raise(StandardError, "explode")
      post "/dashboard/addons/#{database.id}/unlink", params: { app_id: target_app.id }
      expect(response).to redirect_to(dashboard_addon_path(database))
      expect(flash[:alert]).to match(/Unlink failed/)
    end
  end

  it "never references Dokku:: anywhere in the controller (W7 Phase 2 — dokku-free)" do
    source = File.read(Wokku::Engine.root.join("app/controllers/dashboard/databases_controller.rb"))
    expect(source).not_to match(/Dokku::/)
  end

  # ---------------------------------------------------------------------------
  # guard: deletion-pending blocks create
  # ---------------------------------------------------------------------------
  describe "create guard during deletion-pending" do
    it "redirects to dashboard root with an alert" do
      user.update!(deletion_scheduled_at: 2.days.from_now)
      post "/dashboard/addons", params: {
        database_service: { name: "blocked-pg", service_type: "postgres", app_id: target_app.id }
      }
      expect(response).to redirect_to(dashboard_root_path)
    end
  end
end

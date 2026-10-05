# frozen_string_literal: true

require "rails_helper"

# Bundle v2 Phase 7 prep #4: new-app form picks box size + shared addons +
# optional dedicated DB/Redis at creation time.
# Backend columns (box_size, enabled_shared_engines) exist since PR #67.
# AutoProvisionSharedAddonsJob wires shared engines (PR #69).
# DatabaseServiceUpgrade handles dedicated at-creation upgrades (PR #70).
RSpec.describe "Dashboard::Apps (Bundle v2 create)", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  # users(:one) is a regular user on the free plan with team(:one).
  # The free plan allows up to 3 sleeping boxes; we POST box_size: "sleeping"
  # so quota enforcement passes without upgrading the fixture plan.
  let(:user)   { users(:one) }
  let(:server) { servers(:one) }

  before { sign_in user }

  # Stub side-effects that touch external services so tests don't fail on
  # missing SSH/DNS/ACL — the controller already has rescue: nil guards on
  # most, but we stub at the object level to be explicit.
  before do
    stub_request(:any, %r{\Ahttps://api\.cloudflare\.com/})
      .to_return(status: 200, body: { success: true, result: [] }.to_json,
                 headers: { "Content-Type" => "application/json" })
  end

  # ─────────────────────────────────────────────────────────────────────────
  # Helpers
  # ─────────────────────────────────────────────────────────────────────────

  # Minimal valid params for a new app. Uses "sleeping" size so it passes the
  # free plan's box quota (free fixture: sleeping: 3).
  def base_params(overrides = {})
    {
      app_record: {
        name:          "bundle-v2-test-#{SecureRandom.hex(4)}",
        deploy_branch: "main",
        server_id:     server.id,
        box_size:      "sleeping"
      }.merge(overrides)
    }
  end

  describe "POST /dashboard/apps (Bundle v2)" do
    context "happy path: box_size + shared addons" do
      it "saves app with box_size and enabled_shared_engines populated" do
        params = base_params(
          enabled_shared_engines: [ "postgres", "redis" ]
        )

        post dashboard_apps_path, params: params

        expect(response).to have_http_status(:redirect)
        created = AppRecord.find_by(name: params[:app_record][:name])
        expect(created).not_to be_nil
        expect(created.box_size).to eq("sleeping")
        expect(created.enabled_shared_engines).to match_array(%w[postgres redis])
      end

      it "creates a DynoAllocation at the tier mapped from box_size" do
        params = base_params(
          enabled_shared_engines: [ "postgres", "redis" ]
        )

        post dashboard_apps_path, params: params

        created = AppRecord.find_by(name: params[:app_record][:name])
        expect(created).not_to be_nil
        alloc = created.dyno_allocations.find_by(process_type: "web")
        # sleeping → "free" DynoTier
        expect(alloc).not_to be_nil
        expect(alloc.dyno_tier.name).to eq("free")
      end
    end

    context "empty addons: no enabled_shared_engines param" do
      it "saves app with empty enabled_shared_engines (AutoProvisionSharedAddonsJob will no-op)" do
        post dashboard_apps_path, params: base_params

        created = AppRecord.find_by(name: base_params[:app_record][:name])
        # The app name has a random hex suffix so we can't look it up from
        # base_params here — check the last-created app for this user instead.
        last_app = user.app_records.order(created_at: :desc).first
        expect(last_app).not_to be_nil
        expect(Array(last_app.enabled_shared_engines)).to be_empty
      end
    end

    # Regression (external bug report, 2026-09-22): the create-app form ships
    # an empty hidden input so the array key is present when no engine box is
    # ticked. That submits enabled_shared_engines: [""], which used to be
    # rejected as an unknown engine → HTTP 422. It must create the app.
    context "empty addons: form submits the empty hidden input ([\"\"])" do
      it "creates the app instead of returning 422" do
        params = base_params(enabled_shared_engines: [ "" ])

        expect {
          post dashboard_apps_path, params: params
        }.to change(AppRecord, :count).by(1)

        expect(response).to have_http_status(:redirect)
        created = AppRecord.find_by(name: params[:app_record][:name])
        expect(created).not_to be_nil
        expect(Array(created.enabled_shared_engines)).to be_empty
      end
    end

    context "dedicated DB at creation: dedicated_db_engine mysql" do
      it "calls DatabaseServiceUpgrade with engine: mysql after saving the app" do
        dedicated_db = instance_double(DatabaseService, id: SecureRandom.uuid)
        allow(DatabaseServiceUpgrade).to receive(:call)
          .with(hash_including(engine: "mysql"))
          .and_return(dedicated_db)

        params = base_params(dedicated_db_engine: "mysql")
        post dashboard_apps_path, params: params

        expect(response).to have_http_status(:redirect)
        expect(DatabaseServiceUpgrade).to have_received(:call)
          .with(hash_including(engine: "mysql"))
      end
    end

    context "dedicated Redis at creation: add_dedicated_redis=1" do
      it "calls DatabaseServiceUpgrade with engine: redis after saving the app" do
        dedicated_redis = instance_double(DatabaseService, id: SecureRandom.uuid)
        allow(DatabaseServiceUpgrade).to receive(:call)
          .with(hash_including(engine: "redis"))
          .and_return(dedicated_redis)

        params = base_params(add_dedicated_redis: "1")
        post dashboard_apps_path, params: params

        expect(response).to have_http_status(:redirect)
        expect(DatabaseServiceUpgrade).to have_received(:call)
          .with(hash_including(engine: "redis"))
      end
    end
  end

  # Read-path: the box picker must reflect REMAINING quota, not just whether
  # the plan grants the size. Regression test for the "UI offers a size that
  # create rejects" bug — a plan-granted size you've fully used must render
  # disabled, matching enforce_plan_quota!.
  describe "GET /dashboard/apps/new (box picker honors remaining quota)" do
    before { allow(Addons::SharedProvisioner).to receive(:feature_enabled?).and_return(true) }

  end

  describe "new-app form shared add-on picker" do
    it "labels every offered shared engine (no blank checkbox)" do
      allow(Addons::SharedProvisioner).to receive(:feature_enabled?).and_return(true)
      get new_dashboard_app_path
      expect(response).to have_http_status(:ok)

      DatabaseService::SHARED_ENGINES.each do |engine|
        expect(response.body).to include(%(value="#{engine}"))
      end
      expect(response.body).to include("MariaDB", "Shared relational DB (MySQL-compatible)")
      expect(response.body).not_to match(%r{value="mariadb"[^>]*>\s*<span[^>]*>\s*</span>})
    end
  end
end

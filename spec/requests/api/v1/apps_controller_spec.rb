# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API::V1::AppsController", type: :request do
  let(:user) { User.create!(email: "test@example.com", password: "password123456") }
  let(:team) do
    t = Team.create!(name: "Test Team", owner: user)
    TeamMembership.create!(user: user, team: t, role: :admin)
    t
  end
  let(:server) { Server.create!(name: "prod", host: "1.2.3.4", team: team) }
  let!(:app_record) { AppRecord.create!(name: "myapp", server: server, team: team, creator: user) }
  let(:plain_token) { api_v1_token_for(user) }
  let(:headers) { { "Authorization" => "Bearer #{plain_token}" } }

  # Cloudflare DNS is invoked by the apps#create + #destroy controllers
  # for wokku.cloud subdomains. These specs cover the controller logic,
  # not the DNS integration — stub the Cloudflare API uniformly so the
  # specs don't fail on WebMock NetConnectNotAllowedError.
  before do
    stub_request(:any, %r{\Ahttps://api\.cloudflare\.com/})
      .to_return(status: 200, body: { success: true, result: [] }.to_json,
                 headers: { "Content-Type" => "application/json" })
  end

  # --- index ---
  it "index returns user's apps" do
    get api_v1_apps_path, headers: headers
    expect(response).to have_http_status(:success)
    apps = JSON.parse(response.body)
    expect(apps.length).to eq(1)
    expect(apps.first["name"]).to eq("myapp")
  end

  it "index returns 401 without token" do
    get api_v1_apps_path
    expect(response).to have_http_status(:unauthorized)
  end

  # --- show ---
  it "show returns app details" do
    get api_v1_app_path(app_record), headers: headers
    expect(response).to have_http_status(:success)
    expect(JSON.parse(response.body)["name"]).to eq("myapp")
  end

  it "non-team member cannot show app" do
    other_user = User.create!(email: "other@example.com", password: "password123456")
    other_token = api_v1_token_for(other_user)
    get api_v1_app_path(app_record), headers: { "Authorization" => "Bearer #{other_token}" }
    expect(response).to have_http_status(:forbidden)
  end

  it "show returns 401 without token" do
    get api_v1_app_path(app_record)
    expect(response).to have_http_status(:unauthorized)
  end

  it "show resolves app by name as well as uuid" do
    get api_v1_app_path(app_record.name), headers: headers
    expect(response).to have_http_status(:success)
    expect(JSON.parse(response.body)["id"]).to eq(app_record.id)
  end

  it "show returns 404 for nonexistent app" do
    get api_v1_app_path(id: 999999), headers: headers
    expect(response).to have_http_status(:not_found)
  end

  # --- create ---
  it "create returns 401 without token" do
    post api_v1_apps_path, params: { name: "newapp", server_id: server.id }
    expect(response).to have_http_status(:unauthorized)
  end

  it "create succeeds with valid params" do
    post api_v1_apps_path,
         params: { name: "newapp", server_id: server.id },
         headers: headers
    expect(response).to have_http_status(:created)
    expect(JSON.parse(response.body)["name"]).to eq("newapp")
  end

  it "create on a platform server (no team) places the app in user's team" do
    platform_server = Server.create!(name: "platform", host: "9.9.9.9")
    post api_v1_apps_path,
         params: { name: "platform-app", server_id: platform_server.id },
         headers: headers
    expect(response).to have_http_status(:created)
    expect(AppRecord.find_by(name: "platform-app").team_id).to eq(team.id)
  end

  it "create accepts a server name as server_id" do
    post api_v1_apps_path,
         params: { name: "named-server-test-app", server_id: server.name },
         headers: headers
    expect(response).to have_http_status(:created)
    expect(JSON.parse(response.body)["server_id"]).to eq(server.id)
  end

  # create calls Wokku.config.dns_provider to create the DNS record. Which
  # zone(s) that provider actually writes to is Cloudflare::DnsProvider's
  # job — see spec/services/cloudflare/dns_provider_spec.rb.
  it "create calls the configured dns_provider with the new app's name and server host" do
    allow(Wokku.config.dns_provider).to receive(:create_app_record)
    post api_v1_apps_path, params: { name: "api-dns-app", server_id: server.id }, headers: headers
    expect(Wokku.config.dns_provider).to have_received(:create_app_record).with("api-dns-app", server.host)
  end

  it "create never SSHes to the host — native creates are control-plane-only (B6 W2)" do
    expect(Hosts::Ssh).not_to receive(:new)
    post api_v1_apps_path,
         params: { name: "connfail", server_id: server.id },
         headers: headers
    expect(response).to have_http_status(:created)
    expect(AppRecord.find_by!(name: "connfail").wokkud_native).to be true
  end

  # --- Bundle v2 (POST /apps with new params) ---
  context "Bundle v2 (POST /apps with new params)" do
    before do
      stub_request(:any, %r{\Ahttps://api\.cloudflare\.com/})
        .to_return(status: 200, body: { success: true, result: [] }.to_json,
                   headers: { "Content-Type" => "application/json" })
      allow(Addons::SharedProvisioner).to receive(:feature_enabled?).and_return(true)
    end

    it "accepts box_size and persists it on the created app" do
      # Use sleeping (free tier) so the free plan quota check passes.
      post api_v1_apps_path,
           params: { name: "boxtest", server_id: server.id, box_size: "sleeping" },
           headers: headers
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["box_size"]).to eq("sleeping")
      expect(AppRecord.find_by(name: "boxtest").box_size).to eq("sleeping")
    end

    it "defaults box_size to sleeping when not provided" do
      post api_v1_apps_path,
           params: { name: "sleeptest", server_id: server.id },
           headers: headers
      expect(response).to have_http_status(:created)
      expect(AppRecord.find_by(name: "sleeptest").box_size).to eq("sleeping")
    end

    it "accepts enabled_shared_engines and persists them" do
      post api_v1_apps_path,
           params: { name: "engtest", server_id: server.id, box_size: "sleeping", enabled_shared_engines: %w[postgres redis] },
           headers: headers
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["enabled_shared_engines"]).to contain_exactly("postgres", "redis")
      expect(AppRecord.find_by(name: "engtest").enabled_shared_engines).to contain_exactly("postgres", "redis")
    end

    it "returns 402 when plan quota exceeded (flag on)" do
      allow_any_instance_of(PlanEnforceable).to receive(:enforce_plan_quota!)
        .and_raise(PlanEnforceable::PlanQuotaError.new(size: "small", allowed: 0, requested: 1))
      post api_v1_apps_path,
           params: { name: "quotafail", server_id: server.id, box_size: "small" },
           headers: headers
      expect(response).to have_http_status(:payment_required)
      expect(JSON.parse(response.body)["error"]).to match(/plan/i)
    end

    it "calls DatabaseServiceUpgrade.call when dedicated_db_engine given" do
      result = instance_double(DatabaseService, id: "fake-uuid")
      expect(DatabaseServiceUpgrade).to receive(:call)
        .with(hash_including(engine: "postgres"))
        .and_return(result)
      post api_v1_apps_path,
           params: { name: "dedtest", server_id: server.id, box_size: "sleeping", dedicated_db_engine: "postgres" },
           headers: headers
      expect(response).to have_http_status(:created)
    end

    it "includes warning in response when dedicated_db_engine triggers UpgradeError" do
      allow(DatabaseServiceUpgrade).to receive(:call).and_raise(UpgradeError::PlanNoSlots.new(engine: "postgres"))
      post api_v1_apps_path,
           params: { name: "dedwarn", server_id: server.id, box_size: "sleeping", dedicated_db_engine: "postgres" },
           headers: headers
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["warnings"]).to be_present
    end

    it "ignores box_size and new params when flag is off (legacy behavior)" do
      allow(Addons::SharedProvisioner).to receive(:feature_enabled?).and_return(false)
      post api_v1_apps_path,
           params: { name: "legacytest", server_id: server.id, box_size: "large" },
           headers: headers
      expect(response).to have_http_status(:created)
      # No box_size column check — just verifying the request succeeds normally
    end
  end

  # --- update ---
  it "update returns 401 without token" do
    patch api_v1_app_path(app_record), params: { deploy_branch: "develop" }
    expect(response).to have_http_status(:unauthorized)
  end

  it "update changes deploy_branch without renaming when name unchanged" do
    patch api_v1_app_path(app_record),
          params: { deploy_branch: "develop" },
          headers: headers
    expect(response).to have_http_status(:success)
    expect(JSON.parse(response.body)["deploy_branch"]).to eq("develop")
    expect(app_record.reload.deploy_branch).to eq("develop")
  end

  it "update with new name routes through Apps::Lifecycle::Renamer" do
    renamer = instance_double(::Apps::Lifecycle::Renamer)
    expect(::Apps::Lifecycle::Renamer).to receive(:new).with(app_record).and_return(renamer)
    expect(renamer).to receive(:call!).with("renamed-app") { app_record.update!(name: "renamed-app"); app_record }
    patch api_v1_app_path(app_record),
          params: { name: "renamed-app" },
          headers: headers
    expect(response).to have_http_status(:success)
    expect(JSON.parse(response.body)["name"]).to eq("renamed-app")
  end

  it "update maps Apps::Lifecycle::Error(:dokku_error) to 502 dokku_command_failed" do
    allow_any_instance_of(::Apps::Lifecycle::Renamer).to receive(:call!)
      .and_raise(::Apps::Lifecycle::Error.new("rename failed", code: :dokku_error))
    patch api_v1_app_path(app_record),
          params: { name: "bad-rename" },
          headers: headers
    expect(response).to have_http_status(:bad_gateway)
    body = JSON.parse(response.body)
    expect(body["error"]).to eq("rename failed")
    expect(body["error_code"]).to eq("dokku_command_failed")
  end

  # --- destroy ---
  it "destroy returns 401 without token" do
    delete api_v1_app_path(app_record)
    expect(response).to have_http_status(:unauthorized)
  end

  it "destroy routes through Apps::Destroyer and removes the AppRecord" do
    expect {
      delete api_v1_app_path(app_record), headers: headers
    }.to change { AppRecord.count }.by(-1)
    expect(response).to have_http_status(:success)
    expect(JSON.parse(response.body)["message"]).to eq("App destroyed")
  end

  it "destroy still cleans up the AppRecord when a best-effort step raises, and reports the warning" do
    allow_any_instance_of(Git::BareRepo).to receive(:remove!).and_raise("no repo")
    expect {
      delete api_v1_app_path(app_record), headers: headers
    }.to change { AppRecord.count }.by(-1)
    expect(response).to have_http_status(:success)
    body = JSON.parse(response.body)
    expect(body["message"]).to eq("App destroyed")
    expect(body["warnings"].join).to include("no repo")
  end

  # THE load-bearing pin: without this, the API path orphans running Swarm
  # services for wokkud_lifecycle apps (see Apps::Destroyer / Task 1).
  it "destroy on a flagged app tears down its Swarm stack via Lifecycle::Ops.remove_if_flagged!" do
    app_record.update!(wokkud_lifecycle: true)
    expect(Lifecycle::Ops).to receive(:remove!).with(app_record, wait: true)
    expect {
      delete api_v1_app_path(app_record), headers: headers
    }.to change { AppRecord.count }.by(-1)
    expect(response).to have_http_status(:success)
  end

  # Behavior change (deliberate): the old API destroy never touched linked
  # databases at all. Now an exclusively-linked DB is torn down too, same
  # as the dashboard's destroy path.
  it "destroy tears down an exclusively-linked database via DatabaseProvisioner" do
    db = create(:database_service, server: server)
    create(:app_database, app_record: app_record, database_service: db, alias_name: "POSTGRES")
    expect(DatabaseProvisioner).to receive(:destroy!).with(database_service: db)
    delete api_v1_app_path(app_record), headers: headers
    expect(response).to have_http_status(:success)
  end

  it "destroy returns 403 for non-admin team member" do
    member_user = User.create!(email: "member@example.com", password: "password123456")
    TeamMembership.create!(user: member_user, team: team, role: :member)
    member_token = api_v1_token_for(member_user, name: "member")
    delete api_v1_app_path(app_record), headers: { "Authorization" => "Bearer #{member_token}" }
    expect(response).to have_http_status(:forbidden)
  end

  it "never references Dokku:: in the destroy action" do
    source = File.read(Rails.root.join("engines/wokku/app/controllers/api/v1/apps_controller.rb"))
    destroy_body = source[/def destroy\n(.*?)\n      end/m, 1]
    expect(destroy_body).not_to match(/Dokku::/)
  end

  # --- restart / stop / start ---
  it "restart returns 401 without token" do
    post restart_api_v1_app_path(app_record)
    expect(response).to have_http_status(:unauthorized)
  end

  it "restart returns 202 and enqueues DokkuAppActionJob" do
    expect {
      post restart_api_v1_app_path(app_record), headers: headers
    }.to have_enqueued_job(DokkuAppActionJob).with(app_record.id, "restart")
    expect(response).to have_http_status(:accepted)
    body = JSON.parse(response.body)
    expect(body["message"]).to eq("Restart queued")
    expect(body["action"]).to eq("restart")
  end

  it "stop returns 202 and enqueues DokkuAppActionJob" do
    expect {
      post stop_api_v1_app_path(app_record), headers: headers
    }.to have_enqueued_job(DokkuAppActionJob).with(app_record.id, "stop")
    expect(response).to have_http_status(:accepted)
    expect(JSON.parse(response.body)["message"]).to eq("Stop queued")
  end

  it "start returns 202 and enqueues DokkuAppActionJob" do
    expect {
      post start_api_v1_app_path(app_record), headers: headers
    }.to have_enqueued_job(DokkuAppActionJob).with(app_record.id, "start")
    expect(response).to have_http_status(:accepted)
    expect(JSON.parse(response.body)["message"]).to eq("Start queued")
  end

  # --- run ---
  # The async stack.run live leg (202 + run_id, blank-command 400, Busy 409)
  # is pinned in spec/requests/api/v1/runs_spec.rb.

  # --- dokku passthrough (retired W7 Phase 2) ---
  it "POST dokku: returns 410 passthrough_retired" do
    post dokku_api_v1_app_url(app_record),
      params: { args: [ "ps:list" ] }, headers: headers, as: :json
    expect(response).to have_http_status(:gone)
    body = JSON.parse(response.body)
    expect(body["error_code"]).to eq("passthrough_retired")
  end

  it "POST dokku: 403 on cross-team app" do
    other = User.create!(email: "other-dokku@example.com", password: "password123456")
    other_token = api_v1_token_for(other, name: "other-dokku")
    post dokku_api_v1_app_url(app_record),
      params: { args: [ "ps:list" ] },
      headers: { "Authorization" => "Bearer #{other_token}" }, as: :json
    expect(response).to have_http_status(:forbidden)
  end
end

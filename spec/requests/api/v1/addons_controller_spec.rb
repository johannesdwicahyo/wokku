# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API::V1::AddonsController", type: :request do
  let(:user) do
    User.create!(email: "addons-test@example.com", password: "password123456")
  end
  let(:team) do
    t = Team.create!(name: "Addons Team", owner: user)
    TeamMembership.create!(user: user, team: t, role: :admin)
    t
  end
  let(:server) { Server.create!(name: "prod", host: "1.2.3.4", team: team) }
  let(:app_record) { AppRecord.create!(name: "myapp", server: server, team: team, creator: user) }
  let(:database) { DatabaseService.create!(name: "mydb", service_type: "postgres", server: server) }
  let(:plain_token) { api_v1_token_for(user) }
  let(:headers) { { "Authorization" => "Bearer #{plain_token}" } }

  before do
    app_record.app_databases.create!(database_service: database, alias_name: "DATABASE")
  end

  it "index returns 401 without token" do
    get api_v1_app_addons_path(app_record)
    expect(response).to have_http_status(:unauthorized)
  end

  it "index returns app addons" do
    get api_v1_app_addons_path(app_record), headers: headers
    expect(response).to have_http_status(:success)
    addons = JSON.parse(response.body)
    expect(addons).to be_a(Array)
    expect(addons.length).to eq(1)
    expect(addons.first["name"]).to eq("mydb")
    expect(addons.first["service_type"]).to eq("postgres")
  end

  it "index returns empty array when no addons" do
    other_app = AppRecord.create!(name: "emptyapp", server: server, team: team, creator: user)
    get api_v1_app_addons_path(other_app), headers: headers
    expect(response).to have_http_status(:success)
    expect(JSON.parse(response.body)).to eq([])
  end

  it "non-team member cannot access addons" do
    other_user = User.create!(email: "other-addons@example.com", password: "password123456")
    other_token = api_v1_token_for(other_user)
    get api_v1_app_addons_path(app_record), headers: { "Authorization" => "Bearer #{other_token}" }
    expect(response).to have_http_status(:not_found)
  end

  it "index includes shared key per addon" do
    get api_v1_app_addons_path(app_record), headers: headers
    expect(response).to have_http_status(:success)
    addons = JSON.parse(response.body)
    expect(addons.first).to have_key("shared")
    expect(addons.first).to have_key("tier_name")
  end

  # --- Bundle v2 endpoints ---
  context "Bundle v2" do
    it "old POST /addons returns 410 Gone" do
      post api_v1_app_addons_path(app_record),
           params: { service_type: "postgres" },
           headers: headers
      expect(response).to have_http_status(:gone)
      body = JSON.parse(response.body)
      expect(body["deprecated"]).to be true
      expect(body["replacements"]).to have_key("shared")
      expect(body["replacements"]).to have_key("dedicated")
    end

    it "POST /addons/shared with valid engine returns 202 and updates app" do
      allow_any_instance_of(Plan).to receive(:shared_engines_available).and_return(%w[postgres redis memcached])
      post shared_api_v1_app_addons_path(app_record),
           params: { engine: "redis" },
           headers: headers
      expect(response).to have_http_status(:accepted)
      body = JSON.parse(response.body)
      expect(body["engine"]).to eq("redis")
      expect(app_record.reload.enabled_shared_engines).to include("redis")
    end

    it "POST /addons/shared enqueues AutoProvisionSharedAddonsJob" do
      allow_any_instance_of(Plan).to receive(:shared_engines_available).and_return(%w[postgres redis])
      expect {
        post shared_api_v1_app_addons_path(app_record),
             params: { engine: "redis" },
             headers: headers
      }.to have_enqueued_job(AutoProvisionSharedAddonsJob).with(app_record.id)
    end

    it "POST /addons/shared returns 422 for engine not in user plan" do
      # Shared-engine gating goes through the injected enforcer (OSS null allows all).
      allow(Wokku.config.plan_enforcer).to receive(:allowed?)
        .with(anything, :shared_engine, engine: "memcached").and_return(false)
      post shared_api_v1_app_addons_path(app_record),
           params: { engine: "memcached" },
           headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "POST /addons/shared returns 422 for unsupported engine" do
      post shared_api_v1_app_addons_path(app_record),
           params: { engine: "oracle" },
           headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "DELETE /addons/shared/:engine removes engine from app" do
      app_record.update!(enabled_shared_engines: %w[postgres redis])
      allow(DatabaseProvisioner).to receive(:destroy!)
      delete disable_shared_api_v1_app_addons_path(app_record, engine: "redis"),
             headers: headers
      expect(response).to have_http_status(:ok)
      expect(app_record.reload.enabled_shared_engines).not_to include("redis")
    end

    it "POST /addons/dedicated with valid engine returns 202" do
      result = instance_double(DatabaseService, id: "fake-uuid")
      allow(DatabaseServiceUpgrade).to receive(:call).and_return(result)
      post dedicated_api_v1_app_addons_path(app_record),
           params: { engine: "postgres" },
           headers: headers
      expect(response).to have_http_status(:accepted)
      body = JSON.parse(response.body)
      expect(body["dedicated_id"]).to eq("fake-uuid")
    end

    it "POST /addons/dedicated with invalid engine returns 422" do
      post dedicated_api_v1_app_addons_path(app_record),
           params: { engine: "oracle" },
           headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "POST /addons/dedicated with mariadb engine returns 202" do
      result = instance_double(DatabaseService, id: "fake-uuid")
      allow(DatabaseServiceUpgrade).to receive(:call).and_return(result)
      post dedicated_api_v1_app_addons_path(app_record),
           params: { engine: "mariadb" },
           headers: headers
      expect(response).to have_http_status(:accepted)
      body = JSON.parse(response.body)
      expect(body["dedicated_id"]).to eq("fake-uuid")
    end

    it "POST /addons/dedicated with mysql engine returns 422" do
      post dedicated_api_v1_app_addons_path(app_record),
           params: { engine: "mysql" },
           headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "POST /addons/dedicated returns 403 on PlanNoSlots UpgradeError" do
      allow(DatabaseServiceUpgrade).to receive(:call)
        .and_raise(UpgradeError::PlanNoSlots.new(engine: "postgres"))
      post dedicated_api_v1_app_addons_path(app_record),
           params: { engine: "postgres" },
           headers: headers
      expect(response).to have_http_status(:forbidden)
    end

    it "POST /addons/dedicated returns 422 on NoFreeSlots UpgradeError" do
      allow(DatabaseServiceUpgrade).to receive(:call)
        .and_raise(UpgradeError::NoFreeSlots.new(engine: "postgres"))
      post dedicated_api_v1_app_addons_path(app_record),
           params: { engine: "postgres" },
           headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end

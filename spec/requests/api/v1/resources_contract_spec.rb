# frozen_string_literal: true

require "rails_helper"

# Behaviour pins behind the resources OpenAPI batch: another team's app or
# database is a 404 (not a 403 that confirms it exists) on every resource route.
RSpec.describe "API::V1 resource routes contract", type: :request do
  let(:user) { users(:one) }
  let(:foreign_app) { app_records(:two) }
  let(:foreign_db) { database_services(:two) }
  let(:headers) { { "Authorization" => "Bearer #{api_v1_token_for(user)}", "Content-Type" => "application/json" } }
  let(:uuid) { "00000000-0000-0000-0000-000000000000" }

  [
    [ :get, "config" ], [ :patch, "config", { vars: { A: "b" } } ], [ :delete, "config", { keys: [ "A" ] } ],
    [ :get, "domains" ], [ :post, "domains", { hostname: "x.example.com" } ], [ :delete, "domains/UUID" ],
    [ :post, "domains/UUID/ssl" ],
    [ :get, "addons" ], [ :delete, "addons/UUID" ], [ :post, "addons/shared", { engine: "postgres" } ],
    [ :delete, "addons/shared/postgres" ], [ :post, "addons/dedicated", { engine: "postgres" } ],
    [ :get, "scheduled_tasks" ], [ :post, "scheduled_tasks", { command: "ls", schedule: "* * * * *" } ],
    [ :delete, "scheduled_tasks/UUID" ]
  ].each do |verb, suffix, body|
    it "#{verb.upcase} apps/:id/#{suffix} returns 404 for another team's app" do
      send(verb, "/api/v1/apps/#{foreign_app.id}/#{suffix.gsub('UUID', uuid)}", params: (body || {}).to_json, headers: headers)
      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)["error_code"]).to eq("not_found")
    end
  end

  [
    [ :get, "databases/ID" ], [ :delete, "databases/ID" ], [ :get, "databases/ID/monitor" ],
    [ :post, "databases/ID/import" ], [ :post, "databases/ID/link", { app_id: :own } ],
    [ :post, "databases/ID/unlink", { app_id: :own } ],
    [ :get, "databases/ID/backups" ], [ :post, "databases/ID/backups" ],
    [ :get, "databases/ID/backups/UUID/download" ], [ :post, "databases/ID/backups/UUID/restore" ]
  ].each do |verb, suffix, body|
    it "#{verb.upcase} #{suffix} returns 404 for another team's database" do
      body = body&.transform_values { app_records(:one).id }
      send(verb, "/api/v1/#{suffix.sub('ID', foreign_db.id).gsub('UUID', uuid)}", params: (body || {}).to_json, headers: headers)
      expect(response).to have_http_status(:not_found)
    end
  end

  it "POST databases/:id/link returns 404 for another team's app" do
    own_db = database_services(:one)
    post "/api/v1/databases/#{own_db.id}/link", params: { app_id: foreign_app.id }.to_json, headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it "DELETE addons/:id cannot destroy a database that is not this app's" do
    delete "/api/v1/apps/#{app_records(:one).id}/addons/#{foreign_db.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    expect(DatabaseService.exists?(foreign_db.id)).to be(true)
  end

  describe "config writes need member+ (a viewer must not set env vars)" do
    let(:viewer) { create(:user).tap { |u| create(:team_membership, user: u, team: app_records(:one).team, role: :viewer) } }
    let(:viewer_headers) { { "Authorization" => "Bearer #{api_v1_token_for(viewer)}", "Content-Type" => "application/json" } }

    it "PATCH config returns 403 for a viewer" do
      patch "/api/v1/apps/#{app_records(:one).id}/config", params: { vars: { A: "b" } }.to_json, headers: viewer_headers
      expect(response).to have_http_status(:forbidden)
    end

    it "DELETE config returns 403 for a viewer" do
      delete "/api/v1/apps/#{app_records(:one).id}/config", params: { keys: [ "A" ] }.to_json, headers: viewer_headers
      expect(response).to have_http_status(:forbidden)
    end

    it "GET config is still readable by a viewer" do
      get "/api/v1/apps/#{app_records(:one).id}/config", headers: viewer_headers
      expect(response).to have_http_status(:ok)
    end
  end

  describe "role checks on database link/unlink and add-on destroy" do
    let(:team) { app_records(:one).team }
    let(:app_one) { app_records(:one) }
    let(:viewer) { create(:user).tap { |u| create(:team_membership, user: u, team: team, role: :viewer) } }
    let(:member) { create(:user).tap { |u| create(:team_membership, user: u, team: team, role: :member) } }
    let(:db) { servers(:one).database_services.create!(name: "role-pg", service_type: "postgres", status: :running, wokkud_managed: true, dsn: "postgres://user:pass@host:5432/db") }
    let(:json_headers) { ->(u) { { "Authorization" => "Bearer #{api_v1_token_for(u)}", "Content-Type" => "application/json" } } }

    before do
      allow(Apps::Restarter).to receive(:restart)
      allow(Services::Ops).to receive(:issue_and_wait!)
    end

    it "POST link returns 403 for a viewer and writes no env" do
      post "/api/v1/databases/#{db.id}/link", params: { app_id: app_one.id }.to_json, headers: json_headers.(viewer)
      expect(response).to have_http_status(:forbidden)
      expect(AppDatabase.where(database_service: db)).to be_empty
      expect(app_one.env_vars.find_by(key: "POSTGRES_URL")).to be_nil
      expect(Apps::Restarter).not_to have_received(:restart)
    end

    it "POST link still works for a member" do
      post "/api/v1/databases/#{db.id}/link", params: { app_id: app_one.id }.to_json, headers: json_headers.(member)
      expect(response).to have_http_status(:created)
    end

    it "POST unlink returns 403 for a viewer and keeps the env" do
      AppDatabase.create!(app_record: app_one, database_service: db, alias_name: "DB")
      app_one.env_vars.create!(key: "DB_URL", value: "postgres://user:pass@host/db")
      post "/api/v1/databases/#{db.id}/unlink", params: { app_id: app_one.id }.to_json, headers: json_headers.(viewer)
      expect(response).to have_http_status(:forbidden)
      expect(app_one.env_vars.find_by(key: "DB_URL")).to be_present
      expect(AppDatabase.where(database_service: db)).to exist
    end

    it "POST unlink still works for a member" do
      AppDatabase.create!(app_record: app_one, database_service: db, alias_name: "DB")
      post "/api/v1/databases/#{db.id}/unlink", params: { app_id: app_one.id }.to_json, headers: json_headers.(member)
      expect(response).to have_http_status(:ok)
    end

    it "POST unlink returns 404 for another team's app" do
      post "/api/v1/databases/#{database_services(:one).id}/unlink", params: { app_id: foreign_app.id }.to_json, headers: headers
      expect(response).to have_http_status(:not_found)
    end

    context "DELETE addons/:id" do
      before { app_one.app_databases.create!(database_service: db, alias_name: "DATABASE") }

      it "returns 403 for a member and keeps the database" do
        delete "/api/v1/apps/#{app_one.id}/addons/#{db.id}", headers: json_headers.(member)
        expect(response).to have_http_status(:forbidden)
        expect(DatabaseService.exists?(db.id)).to be(true)
      end

      it "succeeds for a team admin" do
        delete "/api/v1/apps/#{app_one.id}/addons/#{db.id}", headers: headers
        expect(response).to have_http_status(:ok)
        expect(DatabaseService.exists?(db.id)).to be(false)
      end
    end

    context "DELETE addons/shared/:engine (destroys the app's shared tenant databases)" do
      let!(:tenant) do
        parent = servers(:one).database_services.create!(name: "shared-redis-parent", service_type: "redis", status: :running)
        servers(:one).database_services.create!(name: "tenant-redis", service_type: "redis", shared: true, parent_service: parent, status: :running)
          .tap { |d| app_one.app_databases.create!(database_service: d, alias_name: "REDIS") }
      end

      it "returns 403 for a member and keeps tenant + enabled engine" do
        app_one.update!(enabled_shared_engines: %w[redis])
        delete "/api/v1/apps/#{app_one.id}/addons/shared/redis", headers: json_headers.(member)
        expect(response).to have_http_status(:forbidden)
        expect(DatabaseService.exists?(tenant.id)).to be(true)
        expect(app_one.reload.enabled_shared_engines).to include("redis")
      end

      it "succeeds for a team admin" do
        allow(DatabaseProvisioner).to receive(:destroy!)
        delete "/api/v1/apps/#{app_one.id}/addons/shared/redis", headers: headers
        expect(response).to have_http_status(:ok)
      end
    end
  end
end

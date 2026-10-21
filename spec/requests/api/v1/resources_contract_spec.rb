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
end

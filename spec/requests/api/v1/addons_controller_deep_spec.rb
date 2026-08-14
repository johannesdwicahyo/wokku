# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API::V1::AddonsController (deep)", type: :request do
  let(:user) { users(:one) }
  let(:app_record) { app_records(:one) }
  let(:plain_token) { api_v1_token_for(user) }
  let(:headers) { { "Authorization" => "Bearer #{plain_token}" } }

  it "index lists existing addons" do
    db = app_record.server.database_services.create!(name: "myapp-postgres", service_type: "postgres", status: :running)
    app_record.app_databases.create!(database_service: db, alias_name: "DATABASE")

    get "/api/v1/apps/#{app_record.id}/addons", headers: headers
    expect(response).to have_http_status(:success)
    body = JSON.parse(response.body)
    expect(body.any? { |a| a["service_type"] == "postgres" }).to be_truthy
  end

  # Legacy POST /addons is collapsed to a permanent 410 — pinned in
  # addons_controller_spec.rb ("old POST /addons returns 410 Gone").

  it "destroy routes through DatabaseProvisioner.destroy! (farewell snapshot + teardown), not raw Dokku:: calls" do
    db = app_record.server.database_services.create!(name: "myapp-postgres", service_type: "postgres", status: :running, wokkud_managed: true)
    app_record.app_databases.create!(database_service: db, alias_name: "DATABASE")
    allow(Services::Ops).to receive(:issue_and_wait!)
    expect(DatabaseProvisioner).to receive(:destroy!).with(database_service: db).and_call_original

    delete "/api/v1/apps/#{app_record.id}/addons/#{db.id}", headers: headers
    expect(response).to have_http_status(:success)
    expect(DatabaseService.exists?(db.id)).to be(false)
  end

  it "destroy tears down a wokkud-managed addon via a service.destroy op — no raw dokku SSH" do
    db = app_record.server.database_services.create!(name: "myapp-postgres", service_type: "postgres", status: :running, wokkud_managed: true)
    app_record.app_databases.create!(database_service: db, alias_name: "DATABASE")
    allow(Services::Ops).to receive(:issue_and_wait!)

    delete "/api/v1/apps/#{app_record.id}/addons/#{db.id}", headers: headers
    expect(Services::Ops).to have_received(:issue_and_wait!)
      .with(service: db, kind: "service.destroy", params: { force: true })
    expect(response).to have_http_status(:success)
    expect(DatabaseService.exists?(db.id)).to be(false)
  end

  # DatabaseProvisioner.destroy! is a deliberately best-effort/idempotent
  # teardown (farewell snapshot + tolerate an already-gone service) — the
  # same design already shipped for Dashboard::DatabasesController#destroy
  # (6a368bdb) and AddonsController#disable_shared. A wokkud teardown
  # failure no longer blocks the request; it's logged and the row removed.
  it "tolerates a wokkud teardown failure and still removes the row + AppDatabase link" do
    db = app_record.server.database_services.create!(name: "myapp-postgres", service_type: "postgres", status: :running, wokkud_managed: true)
    app_database = app_record.app_databases.create!(database_service: db, alias_name: "DATABASE")
    allow(Services::Ops).to receive(:issue_and_wait!).and_raise(Services::Ops::Timeout, "op timed out")

    delete "/api/v1/apps/#{app_record.id}/addons/#{db.id}", headers: headers
    expect(response).to have_http_status(:success)
    expect(DatabaseService.exists?(db.id)).to be(false)
    expect(AppDatabase.exists?(app_database.id)).to be(false)
  end

  it "never references Dokku:: in the destroy action" do
    source = File.read(Wokku::Engine.root.join("app/controllers/api/v1/addons_controller.rb"))
    destroy_body = source[/def destroy\n(.*?)\n      end/m, 1]
    expect(destroy_body).not_to match(/Dokku::/)
  end
end

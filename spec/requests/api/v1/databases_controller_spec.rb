# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API::V1::DatabasesController", type: :request do
  let(:user) do
    u = users(:one)
    u.update!(stripe_payment_method_id: "pm_test")
    u
  end
  let(:team) { teams(:one) }
  let(:server) { servers(:one) }
  let(:plain_token) { api_v1_token_for(user) }
  let(:headers) { { "Authorization" => "Bearer #{plain_token}" } }

  before do
    # W7 Phase 2: create/link/unlink are control-plane writes — no SSH.
    allow(Apps::Restarter).to receive(:restart)
  end

  it "index returns team-scoped databases" do
    server.database_services.create!(name: "pg1", service_type: "postgres", status: :running)
    get "/api/v1/databases", headers: headers
    expect(response).to have_http_status(:success)
    body = JSON.parse(response.body)
    expect(body.any? { |d| d["name"] == "pg1" }).to be_truthy
  end

  it "show returns a specific database" do
    db = server.database_services.create!(name: "pg2", service_type: "postgres", status: :running)
    get "/api/v1/databases/#{db.id}", headers: headers
    expect(response).to have_http_status(:success)
    expect(JSON.parse(response.body)["name"]).to eq("pg2")
  end

  it "create provisions a new database through DatabaseProvisioner (service.create op)" do
    allow(Services::Ops).to receive(:issue_and_wait!)
    expect {
      post "/api/v1/databases",
        params: { server_id: server.id, name: "new-pg", service_type: "postgres" },
        headers: headers
    }.to change { server.database_services.count }.by(1)
    expect(response).to have_http_status(:created)

    db = server.database_services.find_by!(name: "new-pg")
    expect(db.status).to eq("running")
    expect(db.wokkud_managed?).to be(true)
    expect(db.dsn).to start_with("postgres://")
    expect(Services::Ops).to have_received(:issue_and_wait!)
      .with(service: db, kind: "service.create", params: hash_including(service_type: "postgres"))
  end

  it "create carries the tier caps inside the service.create op — no ApplyDatabaseTierJob" do
    allow(Services::Ops).to receive(:issue_and_wait!)
    expect {
      post "/api/v1/databases",
        params: { server_id: server.id, name: "tier-pg", service_type: "postgres" },
        headers: headers
    }.not_to have_enqueued_job(ApplyDatabaseTierJob)
    expect(response).to have_http_status(:created)
  end

  it "create returns 503 when the op times out" do
    allow(Services::Ops).to receive(:issue_and_wait!).and_raise(Services::Ops::Timeout, "not finished after 300s")
    post "/api/v1/databases",
      params: { server_id: server.id, name: "new-pg", service_type: "postgres" },
      headers: headers
    expect(response).to have_http_status(:service_unavailable)
    expect(JSON.parse(response.body)["error_code"]).to eq("service_op_timeout")
  end

  it "create returns 502 when the op fails" do
    op = instance_double(ServiceOp, kind: "service.create", error: "image pull failed", error_code: "create_failed")
    allow(Services::Ops).to receive(:issue_and_wait!).and_raise(Services::Ops::Failed.new(op))
    post "/api/v1/databases",
      params: { server_id: server.id, name: "new-pg", service_type: "postgres" },
      headers: headers
    expect(response).to have_http_status(:bad_gateway)
    body = JSON.parse(response.body)
    expect(body["error"]).to match(/image pull failed/)
    expect(body["error_code"]).to eq("service_create_failed")
  end

  it "create returns 422 for engines wokkud does not support" do
    post "/api/v1/databases",
      params: { server_id: server.id, name: "new-cache", service_type: "memcached" },
      headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)["error"]).to match(/not supported/)
  end

  it "destroy tears down the database" do
    db = server.database_services.create!(name: "goodbye", service_type: "postgres", status: :running, wokkud_managed: true)
    allow(Services::Ops).to receive(:issue_and_wait!)
    expect {
      delete "/api/v1/databases/#{db.id}", headers: headers
    }.to change { server.database_services.count }.by(-1)
    expect(response).to have_http_status(:success)
  end

  it "destroy routes through DatabaseProvisioner.destroy! (farewell snapshot + teardown), not raw Dokku:: calls" do
    db = server.database_services.create!(name: "provisioner-routed", service_type: "postgres", status: :running, wokkud_managed: true)
    allow(Services::Ops).to receive(:issue_and_wait!)
    expect(DatabaseProvisioner).to receive(:destroy!).with(database_service: db).and_call_original
    delete "/api/v1/databases/#{db.id}", headers: headers
    expect(response).to have_http_status(:success)
    expect(DatabaseService.exists?(db.id)).to be(false)
  end

  it "destroy tears down a wokkud-managed database via a service.destroy op — no raw dokku SSH, no 422" do
    db = server.database_services.create!(name: "wokkud-pg", service_type: "postgres", status: :running, wokkud_managed: true)
    allow(Services::Ops).to receive(:issue_and_wait!)
    delete "/api/v1/databases/#{db.id}", headers: headers
    expect(Services::Ops).to have_received(:issue_and_wait!)
      .with(service: db, kind: "service.destroy", params: { force: true })
    expect(response).to have_http_status(:success)
    expect(DatabaseService.exists?(db.id)).to be(false)
  end

  it "destroy tolerates a wokkud teardown failure and still removes the row (DatabaseProvisioner is best-effort/idempotent — matches the dashboard + disable_shared behavior)" do
    db = server.database_services.create!(name: "err-down", service_type: "postgres", status: :running, wokkud_managed: true)
    allow(Services::Ops).to receive(:issue_and_wait!).and_raise(Services::Ops::Timeout, "op timed out")
    delete "/api/v1/databases/#{db.id}", headers: headers
    expect(response).to have_http_status(:success)
    expect(DatabaseService.exists?(db.id)).to be(false)
  end

  it "never references Dokku:: anywhere in the controller (W7 Phase 2 — dokku-free)" do
    source = File.read(Wokku::Engine.root.join("app/controllers/api/v1/databases_controller.rb"))
    expect(source).not_to match(/Dokku::/)
  end

  it "link attaches a database to an app with the canonical alias + env write" do
    db = server.database_services.create!(name: "linkable-pg", service_type: "postgres", status: :running,
                                          dsn: "postgres://u:s@dokku.postgres.linkable-pg:5432/linkable_pg")
    app = app_records(:one)

    expect {
      post "/api/v1/databases/#{db.id}/link", params: { app_id: app.id }, headers: headers
    }.to change { AppDatabase.count }.by(1)
    expect(response).to have_http_status(:created)

    link = AppDatabase.find_by(app_record: app, database_service: db)
    expect(link.alias_name).to eq("POSTGRES")
    expect(app.env_vars.find_by(key: "POSTGRES_URL").value).to eq(db.dsn)
    expect(Apps::Restarter).to have_received(:restart).with(app)
  end

  it "link honors an explicit alias_name param" do
    db = server.database_services.create!(name: "aliased-pg", service_type: "postgres", status: :running,
                                          dsn: "postgres://u:s@h:5432/d")
    app = app_records(:one)
    post "/api/v1/databases/#{db.id}/link", params: { app_id: app.id, alias_name: "PRIMARY" }, headers: headers
    expect(response).to have_http_status(:created)
    expect(app.env_vars.find_by(key: "PRIMARY_URL")).to be_present
  end

  it "link returns 422 when the app is already linked" do
    db = server.database_services.create!(name: "dup-pg", service_type: "postgres", status: :running)
    app = app_records(:one)
    AppDatabase.create!(app_record: app, database_service: db, alias_name: "POSTGRES")
    post "/api/v1/databases/#{db.id}/link", params: { app_id: app.id }, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "unlink detaches a database from an app and unsets the alias'd env var" do
    db = server.database_services.create!(name: "unlink-pg", service_type: "postgres", status: :running)
    app = app_records(:one)
    AppDatabase.create!(app_record: app, database_service: db, alias_name: "DB")
    app.env_vars.create!(key: "DB_URL", value: "postgres://u:s@h:5432/d")

    expect {
      post "/api/v1/databases/#{db.id}/unlink", params: { app_id: app.id }, headers: headers
    }.to change { AppDatabase.count }.by(-1)
    expect(response).to have_http_status(:success)
    expect(app.env_vars.find_by(key: "DB_URL")).to be_nil
  end
end

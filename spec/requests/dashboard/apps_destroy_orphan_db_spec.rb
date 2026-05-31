# frozen_string_literal: true

require "rails_helper"

# Regression: deleting an app that owns exclusively-linked databases used to
# leave the DatabaseService records (and Dokku postgres/redis containers)
# orphaned, racking up daily debits forever. The destroy action now tears
# down each exclusively-linked DB so billing stops the same day.
RSpec.describe "Dashboard::Apps#destroy orphan DB cleanup", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { users(:two) }
  let(:target_app) { app_records(:two) }
  let(:server) { target_app.server }
  let(:dokku_client)    { instance_double(Dokku::Client) }
  let(:dokku_apps)      { instance_double(Dokku::Apps, destroy: true) }
  let(:dokku_databases) { instance_double(Dokku::Databases, destroy: true) }
  let(:cloudflare)      { instance_double(Cloudflare::Dns, delete_app_record: nil) }

  before do
    allow(Dokku::Client).to receive(:new).with(server).and_return(dokku_client)
    allow(Dokku::Apps).to receive(:new).with(dokku_client).and_return(dokku_apps)
    allow(Dokku::Databases).to receive(:new).with(dokku_client).and_return(dokku_databases)
    allow(Cloudflare::Dns).to receive(:new).and_return(cloudflare)
    sign_in user
  end

  it "destroys an exclusively-linked DatabaseService when the app is deleted" do
    db = DatabaseService.create!(name: "#{target_app.name}-orphan-db", service_type: "postgres", server: server)
    AppDatabase.create!(app_record: target_app, database_service: db, alias_name: "POSTGRES")

    expect {
      delete "/dashboard/apps/#{target_app.id}"
    }.to change { DatabaseService.where(id: db.id).count }.by(-1)

    expect(dokku_databases).to have_received(:destroy).with("postgres", "#{target_app.name}-orphan-db")
  end

  it "preserves a database that is shared with another app" do
    other_app = app_records(:one)
    db = DatabaseService.create!(name: "shared-orphan-db", service_type: "postgres", server: server)
    AppDatabase.create!(app_record: target_app, database_service: db, alias_name: "POSTGRES")
    AppDatabase.create!(app_record: other_app, database_service: db, alias_name: "POSTGRES")

    expect {
      delete "/dashboard/apps/#{target_app.id}"
    }.not_to change { DatabaseService.where(id: db.id).count }

    expect(dokku_databases).not_to have_received(:destroy).with("postgres", "shared-orphan-db")
  end

  it "still completes app destroy when DB Dokku call fails" do
    db = DatabaseService.create!(name: "#{target_app.name}-fail-db", service_type: "postgres", server: server)
    AppDatabase.create!(app_record: target_app, database_service: db, alias_name: "POSTGRES")

    allow(dokku_databases).to receive(:destroy).and_raise(Dokku::Client::CommandError, "no such service")

    expect {
      delete "/dashboard/apps/#{target_app.id}"
    }.to change { DatabaseService.where(id: db.id).count }.by(-1)
  end
end

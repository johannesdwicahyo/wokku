# frozen_string_literal: true

require "rails_helper"

RSpec.describe SyncServerJob, type: :job do
  let(:server) { servers(:one) }

  before do
    # Stub Dokku::Client constructor and the inner service objects so we test
    # orchestration only, no SSH.
    allow_any_instance_of(Dokku::Client).to receive(:initialize).and_return(nil)
    allow_any_instance_of(Dokku::Apps).to receive(:initialize).and_return(nil)
    allow_any_instance_of(Dokku::Apps).to receive(:list).and_return([])
    allow_any_instance_of(Dokku::Domains).to receive(:initialize).and_return(nil)
    allow_any_instance_of(Dokku::Domains).to receive(:list).and_return([])
    allow_any_instance_of(Dokku::Databases).to receive(:initialize).and_return(nil)
    allow_any_instance_of(Dokku::Databases).to receive(:list).and_return([])
    allow_any_instance_of(Dokku::Databases).to receive(:info).and_return({ "links" => "" })
  end

  it "sets server to connected on success" do
    allow_any_instance_of(Dokku::Apps).to receive(:list).and_return([ "my-app-one" ])

    described_class.perform_now(server.id)
    expect(server.reload.status).to eq("connected")
  end

  it "creates new apps found on remote" do
    allow_any_instance_of(Dokku::Apps).to receive(:list).and_return([ "my-app-one", "new-remote-app" ])

    expect {
      described_class.perform_now(server.id)
    }.to change { server.app_records.count }.by(1)

    expect(server.app_records.find_by(name: "new-remote-app")).to be_present
  end

  it "removes apps that no longer exist remotely" do
    allow_any_instance_of(Dokku::Apps).to receive(:list).and_return([])

    expect {
      described_class.perform_now(server.id)
    }.to change { server.app_records.count }.by(-1)

    expect(server.app_records.find_by(name: "my-app-one")).to be_nil
  end

  it "sets server to unreachable on connection error" do
    allow_any_instance_of(Dokku::Apps).to receive(:list)
      .and_raise(Dokku::Client::ConnectionError, "connection refused")

    described_class.perform_now(server.id)
    expect(server.reload.status).to eq("unreachable")
  end

  it "syncs domains for existing apps" do
    allow_any_instance_of(Dokku::Apps).to receive(:list).and_return([ "my-app-one" ])
    allow_any_instance_of(Dokku::Domains).to receive(:list).and_return([ "my-app-one.example.com" ])

    described_class.perform_now(server.id)

    app = server.app_records.find_by(name: "my-app-one")
    expect(app.domains.exists?(hostname: "my-app-one.example.com")).to be true
  end

  it "removes stale domains no longer on remote" do
    app = server.app_records.find_by(name: "my-app-one")
    app.domains.create!(hostname: "stale.example.com")

    allow_any_instance_of(Dokku::Apps).to receive(:list).and_return([ "my-app-one" ])
    allow_any_instance_of(Dokku::Domains).to receive(:list).and_return([])

    described_class.perform_now(server.id)

    expect(app.domains.exists?(hostname: "stale.example.com")).to be false
  end

  it "does NOT auto-import Dokku-listed services with no creator + no app links" do
    allow_any_instance_of(Dokku::Apps).to receive(:list).and_return([ "my-app-one" ])
    allow_any_instance_of(Dokku::Databases).to receive(:list) do |_, service_type|
      service_type == "postgres" ? [ "pg-main", "mydb-new" ] : []
    end

    expect {
      described_class.perform_now(server.id)
    }.not_to change { server.database_services.count }

    expect(server.database_services.exists?(name: "mydb-new", service_type: "postgres")).to be false
  end

  it "updates synced_at on all app records" do
    allow_any_instance_of(Dokku::Apps).to receive(:list).and_return([ "my-app-one" ])

    before_t = 1.hour.ago
    server.app_records.update_all(synced_at: before_t)

    described_class.perform_now(server.id)

    server.app_records.reload.each do |app|
      expect(app.synced_at).to be > before_t
    end
  end
end

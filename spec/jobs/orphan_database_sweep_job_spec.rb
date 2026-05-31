# frozen_string_literal: true

require "rails_helper"

RSpec.describe OrphanDatabaseSweepJob, type: :job do
  let(:server) { servers(:two) }
  let(:dokku_client) { instance_double(Dokku::Client) }
  let(:dokku_databases) { instance_double(Dokku::Databases, destroy: true) }

  before do
    allow(Dokku::Client).to receive(:new).with(server).and_return(dokku_client)
    allow(Dokku::Databases).to receive(:new).with(dokku_client).and_return(dokku_databases)
  end

  it "destroys an unattached dedicated DB older than the grace period" do
    db = DatabaseService.create!(
      name: "orphan-db", service_type: "postgres", server: server,
      created_at: 2.days.ago
    )

    expect(dokku_databases).to receive(:destroy).with("postgres", "orphan-db")

    expect {
      described_class.new.perform
    }.to change { DatabaseService.where(id: db.id).count }.by(-1)
  end

  it "leaves an unattached DB inside the grace period alone" do
    db = DatabaseService.create!(
      name: "fresh-orphan-db", service_type: "postgres", server: server,
      created_at: 10.minutes.ago
    )

    expect(dokku_databases).not_to receive(:destroy)

    expect {
      described_class.new.perform
    }.not_to change { DatabaseService.where(id: db.id).count }
  end

  it "leaves attached DBs alone regardless of age" do
    db = DatabaseService.create!(
      name: "linked-db", service_type: "postgres", server: server,
      created_at: 30.days.ago
    )
    AppDatabase.create!(app_record: app_records(:two), database_service: db, alias_name: "POSTGRES")

    expect {
      described_class.new.perform
    }.not_to change { DatabaseService.where(id: db.id).count }
  end

  it "skips shared-tenant rows (managed by SharedDatabaseQuotaJob)" do
    # Shared tenants are excluded by the `dedicated` scope (shared: true).
    # Use update_columns to bypass the shared_tenants_must_have_parent
    # validation — we only need a row with shared: true for the scope filter.
    db = DatabaseService.create!(name: "shared-tenant", service_type: "postgres", server: server)
    db.update_columns(shared: true, created_at: 30.days.ago)

    expect {
      described_class.new.perform
    }.not_to change { DatabaseService.where(id: db.id).count }
  end

  it "still destroys the DB record when Dokku::Databases#destroy errors" do
    db = DatabaseService.create!(
      name: "dokku-error-db", service_type: "postgres", server: server,
      created_at: 2.days.ago
    )
    allow(dokku_databases).to receive(:destroy).and_raise(Dokku::Client::CommandError, "no such service")

    expect {
      described_class.new.perform
    }.to change { DatabaseService.where(id: db.id).count }.by(-1)
  end
end

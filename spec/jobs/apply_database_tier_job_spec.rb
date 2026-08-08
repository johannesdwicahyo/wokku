# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplyDatabaseTierJob, type: :job do
  let(:server) { create(:server) }

  before do
    allow(Services::Ops).to receive(:issue_and_wait!)
  end

  def make_tier(name:, service_type: "postgres", spec: {})
    ServiceTier.find_or_create_by!(name: name, service_type: service_type) do |t|
      t.price_cents_per_hour = 0
    end.tap { |t| t.update_columns(spec: spec) }
  end

  describe "guard / early-return branches" do
    it "returns early when the database service does not exist" do
      described_class.perform_now("00000000-0000-0000-0000-000000000000")
      expect(Services::Ops).not_to have_received(:issue_and_wait!)
    end

    it "returns early for shared tenants (governed by SharedDatabaseQuotaJob)" do
      parent = create(:database_service, server: server, name: "dokku-shared-postgres")
      shared = create(
        :database_service, server: server, shared: true,
        parent_service: parent, name: "shared-tenant"
      )

      described_class.perform_now(shared.id)
      expect(Services::Ops).not_to have_received(:issue_and_wait!)
    end

    it "returns early when the service has no resolvable tier" do
      db = create(:database_service, server: server, tier_name: "does-not-exist")
      allow(db).to receive(:service_tier).and_return(nil)
      allow(DatabaseService).to receive(:find_by).with(id: db.id).and_return(db)

      described_class.perform_now(db.id)
      expect(Services::Ops).not_to have_received(:issue_and_wait!)
    end

    it "skips the op when the tier spec carries no limits" do
      make_tier(name: "empty", spec: {})
      db = create(:database_service, server: server, tier_name: "empty")

      described_class.perform_now(db.id)
      expect(Services::Ops).not_to have_received(:issue_and_wait!)
    end
  end

  describe "applying tier resources" do
    it "issues a service.set_limits op with the tier's memory and connections" do
      make_tier(name: "conn", spec: { "memory_mb" => 1024, "connections" => 100 })
      db = create(:database_service, server: server, tier_name: "conn")

      described_class.perform_now(db.id)

      expect(Services::Ops).to have_received(:issue_and_wait!)
        .with(service: db, kind: "service.set_limits",
              params: { memory_mb: 1024, max_connections: 100 })
    end

    it "issues the op with a zero connections cap when the tier is memory-only" do
      make_tier(name: "ram-only", spec: { "memory_mb" => 512 })
      db = create(:database_service, server: server, tier_name: "ram-only")

      described_class.perform_now(db.id)

      expect(Services::Ops).to have_received(:issue_and_wait!)
        .with(service: db, kind: "service.set_limits",
              params: { memory_mb: 512, max_connections: 0 })
    end

    it "supports symbol-keyed spec hashes" do
      make_tier(name: "sym", spec: {})
      db = create(:database_service, server: server, tier_name: "sym")
      tier = db.service_tier
      allow(tier).to receive(:spec).and_return(memory_mb: 256, connections: 50)
      allow_any_instance_of(DatabaseService).to receive(:service_tier).and_return(tier)

      described_class.perform_now(db.id)

      expect(Services::Ops).to have_received(:issue_and_wait!)
        .with(service: db, kind: "service.set_limits",
              params: { memory_mb: 256, max_connections: 50 })
    end
  end

  describe "activity tracking" do
    it "logs an activity when the database is linked to an app with a creator + team" do
      make_tier(name: "tracked", spec: { "memory_mb" => 512 })
      db = create(:database_service, server: server, tier_name: "tracked")
      app = create(:app_record, server: server)
      create(:app_database, app_record: app, database_service: db)

      expect {
        described_class.perform_now(db.id)
      }.to change(Activity, :count).by(1)

      activity = Activity.last
      expect(activity.action).to eq("database.tier_changed")
      expect(activity.metadata["service_type"]).to eq("postgres")
    end

    it "does not log when the database has no linked app" do
      make_tier(name: "untracked", spec: { "memory_mb" => 512 })
      db = create(:database_service, server: server, tier_name: "untracked")

      expect {
        described_class.perform_now(db.id)
      }.not_to change(Activity, :count)
    end

    it "swallows activity-logging errors without failing the job" do
      make_tier(name: "logfail", spec: { "memory_mb" => 512 })
      db = create(:database_service, server: server, tier_name: "logfail")
      app = create(:app_record, server: server)
      create(:app_database, app_record: app, database_service: db)
      allow(Activity).to receive(:log).and_raise(StandardError, "log boom")

      expect { described_class.perform_now(db.id) }.not_to raise_error
    end
  end

  describe "error handling" do
    it "logs, reports to Sentry, and re-raises when the op fails" do
      make_tier(name: "boom", spec: { "memory_mb" => 512 })
      db = create(:database_service, server: server, tier_name: "boom")
      op = instance_double(ServiceOp, kind: "service.set_limits", error: "agent boom", error_code: "set_limits_failed")
      allow(Services::Ops).to receive(:issue_and_wait!).and_raise(Services::Ops::Failed.new(op))
      allow(Sentry).to receive(:capture_exception)

      expect { described_class.perform_now(db.id) }.to raise_error(Services::Ops::Failed)
      # at_least: sentry-rails' ActiveJob integration also captures the re-raise.
      expect(Sentry).to have_received(:capture_exception).at_least(:once)
    end

    it "re-raises on an op timeout" do
      make_tier(name: "cmdboom", spec: { "connections" => 100 })
      db = create(:database_service, server: server, tier_name: "cmdboom")
      allow(Services::Ops).to receive(:issue_and_wait!).and_raise(Services::Ops::Timeout, "not finished")
      allow(Sentry).to receive(:capture_exception)

      expect { described_class.perform_now(db.id) }
        .to raise_error(Services::Ops::Timeout)
    end
  end
end

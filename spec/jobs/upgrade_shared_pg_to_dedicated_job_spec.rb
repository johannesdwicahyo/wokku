require "rails_helper"

RSpec.describe UpgradeSharedPgToDedicatedJob do
  let(:server) { create(:server) }
  let(:user)   { create(:user) }
  # Fleet reality (W7): every app is Swarm-run — restarts go through
  # Apps::Restarter -> Lifecycle::Ops.converge!, which already waits; the
  # old dokku ps:report health poll is gone.
  let(:app)    { create(:app_record, creator: user, server: server, wokkud_lifecycle: true) }
  let(:parent) { DatabaseService.create!(server: server, name: "dokku-shared-postgres", service_type: "postgres", tier_name: "shared_host", shared: false, status: :running, wokkud_managed: true) }

  let!(:shared) do
    db = DatabaseService.create!(
      server: server, parent_service: parent, name: "src-pg",
      service_type: "postgres", tier_name: DatabaseProvisioner::SHARED_TIER,
      shared: true, status: :running, creator: user,
      shared_role_name: "src_role", shared_db_name: "src_db", live_db_bytes: 10 * 1024 * 1024
    )
    AppDatabase.create!(app_record: app, database_service: db, alias_name: "DATABASE")
    db
  end

  let!(:dedicated) do
    DatabaseService.create!(
      server: server, name: "#{app.name}-postgres-dedicated",
      service_type: "postgres", tier_name: "basic", shared: false,
      status: :upgrading_provisioning, creator: user, upgrade_source_id: shared.id
    )
  end

  let!(:destination) do
    server.create_backup_destination!(
      enabled: true, provider: "r2", bucket: "wokku-backups",
      path_prefix: "dbs/#{server.name}", access_key_id: "AKID",
      secret_access_key: "SECRET", region: "auto"
    )
  end

  let(:succeeded_op) { build_stubbed(:service_op, status: :succeeded) }
  let(:ops_log) { [] }

  before do
    app.env_vars.create!(key: "DATABASE_URL", value: "postgres://src_role:oldpw@dokku-shared-postgres:5432/src_db")
    allow(Services::Ops).to receive(:issue_and_wait!) do |service:, kind:, params:|
      ops_log << { service: service, kind: kind, params: params }
      succeeded_op
    end
    allow(Apps::Restarter).to receive(:restart)
  end

  it "walks the state machine to :running and flips DATABASE_URL to the op-composed DSN" do
    described_class.new.perform(dedicated.id)

    expect(dedicated.reload.status).to eq("running")
    expect(dedicated.wokkud_managed).to be(true)
    expect(dedicated.dsn).to match(%r{\Apostgres://postgres:\h{32}@dokku\.postgres\.#{Regexp.escape(dedicated.name)}:5432/})
    expect(shared.reload.status).to eq("pending_destroy")
    expect(shared.reload.pending_destroy_at).to be_present
    expect(app.env_vars.find_by(key: "DATABASE_URL")&.value).to eq(dedicated.dsn)
    expect(Apps::Restarter).to have_received(:restart).with(app)
  end

  it "provisions via service.create and relays export (parent) -> R2 -> import (dedicated)" do
    described_class.new.perform(dedicated.id)

    expect(ops_log[0]).to include(service: dedicated, kind: "service.create")
    expect(ops_log[0][:params]).to include(service_type: "postgres", network: DatabaseProvisioner::DEDICATED_NETWORK)
    expect(ops_log[1][:service]).to eq(parent)
    expect(ops_log[1][:kind]).to eq("service.export")
    expect(ops_log[1][:params]).to include(service_type: "postgres", database: "src_db")
    expect(ops_log[1][:params][:presigned_put_url]).to be_a(String)
    expect(ops_log[2][:service]).to eq(dedicated)
    expect(ops_log[2][:kind]).to eq("service.import")
    expect(ops_log[2][:params]).to include(service_type: "postgres", database: dedicated.name)
    expect(ops_log[2][:params][:presigned_get_url]).to be_a(String)
  end

  it "re-links the AppDatabase row from shared → dedicated" do
    described_class.new.perform(dedicated.id)
    aliases = app.app_databases.where(alias_name: "DATABASE").map(&:database_service_id)
    expect(aliases).to eq([ dedicated.id ])
  end

  it "schedules DropSharedTenantJob 24h out" do
    expect {
      described_class.new.perform(dedicated.id)
    }.to have_enqueued_job(DropSharedTenantJob).with(shared.id).at(a_value_within(60.seconds).of(24.hours.from_now))
  end

  describe "rollback paths" do
    context "when step 1 (provision) fails" do
      before do
        allow(Services::Ops).to receive(:issue_and_wait!) do |service:, kind:, params:|
          ops_log << { service: service, kind: kind, params: params }
          raise Services::Ops::Failed, build_stubbed(:service_op, status: :failed, error: "boom") if kind == "service.create"
          succeeded_op
        end
      end

      it "destroys the dedicated row + issues service.destroy, leaves shared intact" do
        expect { described_class.new.perform(dedicated.id) }.to raise_error(Services::Ops::Failed)
        expect(DatabaseService.exists?(dedicated.id)).to eq(false)
        expect(shared.reload.status).to eq("running")
        expect(ops_log).to include(hash_including(service: dedicated, kind: "service.destroy", params: { force: true }))
      end
    end

    context "when step 3 (migration) fails" do
      before do
        allow(Services::Ops).to receive(:issue_and_wait!) do |service:, kind:, params:|
          ops_log << { service: service, kind: kind, params: params }
          raise Services::Ops::Timeout, "export timed out" if kind == "service.export"
          succeeded_op
        end
      end

      it "destroys dedicated + container, leaves shared on running, no DATABASE_URL change" do
        expect { described_class.new.perform(dedicated.id) }.to raise_error(Services::Ops::Timeout)
        expect(DatabaseService.exists?(dedicated.id)).to eq(false)
        expect(shared.reload.status).to eq("running")
        expect(app.env_vars.find_by(key: "DATABASE_URL")&.value)
          .to eq("postgres://src_role:oldpw@dokku-shared-postgres:5432/src_db")
        expect(ops_log).to include(hash_including(service: dedicated, kind: "service.destroy", params: { force: true }))
      end
    end

    context "when step 5 (the post-cutover restart converge) fails" do
      before do
        # First restart (cutover) fails; the rollback's own restart succeeds.
        calls = 0
        allow(Apps::Restarter).to receive(:restart) do
          calls += 1
          raise Lifecycle::Ops::Timeout, "converge poll timed out" if calls == 1
        end
      end

      it "re-flips DATABASE_URL back to the captured pre-cutover URL, destroys dedicated, leaves shared running" do
        expect { described_class.new.perform(dedicated.id) }.to raise_error(Lifecycle::Ops::Timeout)

        expect(app.env_vars.find_by(key: "DATABASE_URL")&.value)
          .to eq("postgres://src_role:oldpw@dokku-shared-postgres:5432/src_db")
        expect(DatabaseService.exists?(dedicated.id)).to eq(false)
        expect(shared.reload.status).to eq("running")
        expect(app.app_databases.where(alias_name: "DATABASE").map(&:database_service_id)).to eq([ shared.id ])
      end
    end
  end
end

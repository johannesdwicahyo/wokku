require "rails_helper"

RSpec.describe UpgradeSharedPgToDedicatedJob do
  let(:server) { create(:server) }
  let(:user)   { create(:user) }
  let(:app)    { create(:app_record, creator: user, server: server) }
  let(:parent) { DatabaseService.create!(server: server, name: "dokku-shared-postgres", service_type: "postgres", tier_name: "shared_host", shared: false, status: :running) }

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

  let(:client)        { instance_double(Dokku::Client) }
  let(:databases)     { instance_double(Dokku::Databases) }
  let(:db_resources)  { instance_double(Dokku::DatabaseResources, apply: true) }
  let(:dokku_config)  { instance_double(Dokku::Config, set: true) }
  let(:dokku_apps)    { instance_double(Dokku::Apps) }
  let(:processes)     { instance_double(Dokku::Processes, restart: true) }

  before do
    allow(Dokku::Client).to             receive(:new).with(server).and_return(client)
    allow(Dokku::Databases).to          receive(:new).with(client).and_return(databases)
    allow(Dokku::DatabaseResources).to  receive(:new).with(client).and_return(db_resources)
    allow(Dokku::Config).to             receive(:new).with(client).and_return(dokku_config)
    allow(Dokku::Apps).to               receive(:new).with(client).and_return(dokku_apps)
    allow(Dokku::Processes).to          receive(:new).with(client).and_return(processes)
    allow(databases).to                 receive(:create).with("postgres", dedicated.name)
    allow(databases).to                 receive(:info).with("postgres", dedicated.name)
                                                      .and_return("dsn" => "postgres://x:y@dedi:5432/db")
    allow(client).to                    receive(:run).with(/sh -c/, anything).and_return("")
    allow(client).to                    receive(:run).with("ps:report #{Shellwords.escape(app.name)}", anything)
                                                      .and_return("Status: running\n")
  end

  it "walks the state machine to :running and flips DATABASE_URL" do
    described_class.new.perform(dedicated.id)
    expect(dedicated.reload.status).to eq("running")
    expect(shared.reload.status).to    eq("pending_destroy")
    expect(shared.reload.pending_destroy_at).to be_present
    expect(dokku_config).to have_received(:set).with(app.name, hash_including("DATABASE_URL" => "postgres://x:y@dedi:5432/db"))
    expect(processes).to have_received(:restart).with(app.name)
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
    before do
      allow(databases).to receive(:destroy).with("postgres", dedicated.name)
    end

    context "when step 1 (provision) fails" do
      before do
        allow(databases).to receive(:create).with("postgres", dedicated.name).and_raise(Dokku::Client::CommandError, "boom")
      end

      it "destroys the dedicated row + container, leaves shared intact, status not changed on shared" do
        expect { described_class.new.perform(dedicated.id) }.to raise_error(Dokku::Client::CommandError)
        expect(DatabaseService.exists?(dedicated.id)).to eq(false)
        expect(shared.reload.status).to eq("running")
        expect(databases).to have_received(:destroy).with("postgres", dedicated.name)
      end
    end

    context "when step 3 (migration) fails" do
      before do
        allow(client).to receive(:run).with(/sh -c/, anything).and_raise(Dokku::Client::CommandError, "pg_restore boom")
      end

      it "destroys dedicated + container, leaves shared on running, no DATABASE_URL change" do
        expect { described_class.new.perform(dedicated.id) }.to raise_error(Dokku::Client::CommandError)
        expect(DatabaseService.exists?(dedicated.id)).to eq(false)
        expect(shared.reload.status).to eq("running")
        expect(dokku_config).not_to have_received(:set)
      end
    end

    context "when step 5 (restart) is unhealthy" do
      before do
        allow(client).to receive(:run).with("ps:report #{Shellwords.escape(app.name)}", anything).and_return("Status: stopped\n")
        stub_const("UpgradeSharedPgToDedicatedJob::HEALTH_POLL_MAX_WAIT", 0)
        stub_const("UpgradeSharedPgToDedicatedJob::HEALTH_POLL_INTERVAL", 0)
      end

      it "re-flips DATABASE_URL back to shared, restarts again, destroys dedicated row, leaves shared running" do
        shared_url_lookup = instance_double(Dokku::SharedPostgres)
        allow(Dokku::SharedPostgres).to receive(:new).with(client).and_return(shared_url_lookup)
        allow(shared_url_lookup).to receive(:info).with("src").and_return(connection_url: "postgres://shared:url@host/db")

        expect { described_class.new.perform(dedicated.id) }.to raise_error(UpgradeError::CutoverFailed)

        expect(dokku_config).to have_received(:set).with(app.name, hash_including("DATABASE_URL" => "postgres://shared:url@host/db"))
        expect(DatabaseService.exists?(dedicated.id)).to eq(false)
        expect(shared.reload.status).to eq("running")
        expect(app.app_databases.where(alias_name: "DATABASE").map(&:database_service_id)).to eq([ shared.id ])
      end
    end
  end
end

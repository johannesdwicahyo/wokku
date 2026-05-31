require "rails_helper"

RSpec.describe UpgradeSharedRedisToDedicatedJob do
  let(:server) { create(:server) }
  let(:user)   { create(:user) }
  let(:app)    { create(:app_record, creator: user, server: server) }
  let(:redis_parent) { DatabaseService.create!(server: server, name: "dokku-shared-redis", service_type: "redis", tier_name: "shared_host", shared: false, status: :running) }

  let!(:shared) do
    db = DatabaseService.create!(
      server: server, parent_service: redis_parent, name: "src-redis",
      service_type: "redis", tier_name: DatabaseProvisioner::SHARED_TIER,
      shared: true, status: :running, creator: user,
      shared_role_name: "src_role", live_db_bytes: 5 * 1024 * 1024
    )
    AppDatabase.create!(app_record: app, database_service: db, alias_name: "REDIS")
    db
  end

  let!(:dedicated) do
    DatabaseService.create!(
      server: server, name: "#{app.name}-redis-dedicated",
      service_type: "redis", tier_name: "basic", shared: false,
      status: :upgrading_provisioning, creator: user, upgrade_source_id: shared.id
    )
  end

  let(:client)        { instance_double(Dokku::Client) }
  let(:databases)     { instance_double(Dokku::Databases) }
  let(:db_resources)  { instance_double(Dokku::DatabaseResources, apply: true) }
  let(:dokku_config)  { instance_double(Dokku::Config, set: true) }
  let(:processes)     { instance_double(Dokku::Processes, restart: true) }

  before do
    allow(Dokku::Client).to            receive(:new).with(server).and_return(client)
    allow(Dokku::Databases).to         receive(:new).with(client).and_return(databases)
    allow(Dokku::DatabaseResources).to receive(:new).with(client).and_return(db_resources)
    allow(Dokku::Config).to            receive(:new).with(client).and_return(dokku_config)
    allow(Dokku::Processes).to         receive(:new).with(client).and_return(processes)
    allow(databases).to                receive(:create).with("redis", dedicated.name)
    allow(databases).to                receive(:info).with("redis", dedicated.name)
                                                     .and_return("dsn" => "redis://x:y@dedi:6379/0")
    allow(client).to                   receive(:run).with(/sh -c/, anything).and_return("")
    allow(client).to                   receive(:run).with("ps:report #{Shellwords.escape(app.name)}", anything)
                                                    .and_return("Status: running\n")
  end

  it "walks the state machine to :running and flips REDIS_URL" do
    described_class.new.perform(dedicated.id)
    expect(dedicated.reload.status).to eq("running")
    expect(shared.reload.status).to    eq("pending_destroy")
    expect(shared.reload.pending_destroy_at).to be_present
    expect(dokku_config).to have_received(:set).with(app.name, hash_including("REDIS_URL" => "redis://x:y@dedi:6379/0"))
    expect(processes).to have_received(:restart).with(app.name)
  end

  it "re-links the AppDatabase row from shared → dedicated with alias REDIS" do
    described_class.new.perform(dedicated.id)
    aliases = app.app_databases.where(alias_name: "REDIS").map(&:database_service_id)
    expect(aliases).to eq([ dedicated.id ])
  end

  it "schedules DropSharedRedisTenantJob 24h out" do
    expect {
      described_class.new.perform(dedicated.id)
    }.to have_enqueued_job(DropSharedRedisTenantJob).with(shared.id).at(a_value_within(60.seconds).of(24.hours.from_now))
  end

  describe "rollback paths" do
    before do
      allow(databases).to receive(:destroy).with("redis", dedicated.name)
    end

    context "when step 1 (provision) fails" do
      before do
        allow(databases).to receive(:create).with("redis", dedicated.name).and_raise(Dokku::Client::CommandError, "boom")
      end

      it "destroys the dedicated row + container, leaves shared intact" do
        expect { described_class.new.perform(dedicated.id) }.to raise_error(Dokku::Client::CommandError)
        expect(DatabaseService.exists?(dedicated.id)).to eq(false)
        expect(shared.reload.status).to eq("running")
        expect(databases).to have_received(:destroy).with("redis", dedicated.name)
      end
    end

    context "when step 3 (migration) fails" do
      before do
        allow(client).to receive(:run).with(/sh -c/, anything).and_raise(Dokku::Client::CommandError, "redis-cli pipe boom")
      end

      it "destroys dedicated + container, leaves shared running, no REDIS_URL change" do
        expect { described_class.new.perform(dedicated.id) }.to raise_error(Dokku::Client::CommandError)
        expect(DatabaseService.exists?(dedicated.id)).to eq(false)
        expect(shared.reload.status).to eq("running")
        expect(dokku_config).not_to have_received(:set)
      end
    end

    context "when step 5 (restart) is unhealthy" do
      before do
        allow(client).to receive(:run).with("ps:report #{Shellwords.escape(app.name)}", anything).and_return("Status: stopped\n")
        stub_const("UpgradeSharedRedisToDedicatedJob::HEALTH_POLL_MAX_WAIT", 0)
        stub_const("UpgradeSharedRedisToDedicatedJob::HEALTH_POLL_INTERVAL", 0)
      end

      it "re-flips REDIS_URL back to shared, restarts again, destroys dedicated row, leaves shared running" do
        shared_url_lookup = instance_double(Dokku::SharedRedis)
        allow(Dokku::SharedRedis).to receive(:new).with(client).and_return(shared_url_lookup)
        allow(shared_url_lookup).to receive(:info).with("src").and_return(connection_url: "redis://shared:url@host/0")

        expect { described_class.new.perform(dedicated.id) }.to raise_error(UpgradeError::CutoverFailed)

        expect(dokku_config).to have_received(:set).with(app.name, hash_including("REDIS_URL" => "redis://shared:url@host/0"))
        expect(DatabaseService.exists?(dedicated.id)).to eq(false)
        expect(shared.reload.status).to eq("running")
        expect(app.app_databases.where(alias_name: "REDIS").map(&:database_service_id)).to eq([ shared.id ])
      end
    end
  end
end

require "rails_helper"

RSpec.describe UpgradeSharedRedisToDedicatedJob do
  let(:server) { create(:server) }
  let(:user)   { create(:user) }
  # Fleet reality (W7): every app is Swarm-run — restarts go through
  # Apps::Restarter -> Lifecycle::Ops.converge!, which already waits; the
  # old dokku ps:report health poll is gone.
  let(:app)    { create(:app_record, creator: user, server: server, wokkud_lifecycle: true) }
  let(:redis_parent) { DatabaseService.create!(server: server, name: "dokku-shared-redis", service_type: "redis", tier_name: "shared_host", shared: false, status: :running, wokkud_managed: true) }

  let!(:shared) do
    db = DatabaseService.create!(
      server: server, parent_service: redis_parent, name: "src-redis",
      service_type: "redis", tier_name: DatabaseProvisioner::SHARED_TIER,
      shared: true, status: :running, creator: user,
      shared_role_name: "src", live_db_bytes: 5 * 1024 * 1024
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

  let(:succeeded_op) { build_stubbed(:service_op, status: :succeeded) }
  let(:ops_log) { [] }
  let(:ssh) { instance_double(Hosts::Ssh) }
  let(:ssh_scripts) { [] }

  before do
    app.env_vars.create!(key: "REDIS_URL", value: "redis://src:oldpw@dokku-shared-redis:6379/0")
    allow(Services::Ops).to receive(:issue_and_wait!) do |service:, kind:, params:|
      ops_log << { service: service, kind: kind, params: params }
      succeeded_op
    end
    allow(Hosts::Ssh).to receive(:new).with(server).and_return(ssh)
    allow(ssh).to receive(:run_raw) do |_cmd, timeout: nil, stdin: nil|
      ssh_scripts << stdin
      ""
    end
    allow(Apps::Restarter).to receive(:restart)
  end

  it "walks the state machine to :running and flips REDIS_URL to the op-composed DSN" do
    described_class.new.perform(dedicated.id)

    expect(dedicated.reload.status).to eq("running")
    expect(dedicated.wokkud_managed).to be(true)
    expect(dedicated.dsn).to match(%r{\Aredis://:\h{32}@dokku\.redis\.#{Regexp.escape(dedicated.name)}:6379/0\z})
    expect(shared.reload.status).to eq("pending_destroy")
    expect(shared.reload.pending_destroy_at).to be_present
    expect(app.env_vars.find_by(key: "REDIS_URL")&.value).to eq(dedicated.dsn)
    expect(Apps::Restarter).to have_received(:restart).with(app)
  end

  it "provisions via service.create (no database param for redis)" do
    described_class.new.perform(dedicated.id)

    expect(ops_log[0]).to include(service: dedicated, kind: "service.create")
    expect(ops_log[0][:params]).to include(service_type: "redis", database: "", network: DatabaseProvisioner::DEDICATED_NETWORK)
  end

  it "migrates via a root docker pipe: tenant-ACL SCAN/DUMP export on the parent into the dedicated redis-cli --pipe" do
    described_class.new.perform(dedicated.id)

    script = ssh_scripts.sole
    dedicated_pass = URI.parse(dedicated.reload.dsn).password
    # Export leg: the shared parent, authenticated as the tenant's ACL user
    # (creds from the pre-cutover REDIS_URL), scoped to its key prefix.
    expect(script).to include("docker exec dokku-shared-redis redis-cli --user src --pass oldpw --no-auth-warning")
    expect(script).to include("SCAN \"$cursor\" MATCH src:\\* COUNT 1000")
    expect(script).to include("RESTORE")
    # Import leg: the dedicated container's redis-cli --pipe, admin-authed.
    expect(script).to include("docker exec -i dokku.redis.#{dedicated.name} redis-cli -a #{dedicated_pass} --no-auth-warning --pipe")
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
        allow(ssh).to receive(:run_raw).and_raise(Hosts::Ssh::CommandError.new("redis-cli pipe boom"))
      end

      it "destroys dedicated + container, leaves shared running, no REDIS_URL change" do
        expect { described_class.new.perform(dedicated.id) }.to raise_error(Hosts::Ssh::CommandError)
        expect(DatabaseService.exists?(dedicated.id)).to eq(false)
        expect(shared.reload.status).to eq("running")
        expect(app.env_vars.find_by(key: "REDIS_URL")&.value).to eq("redis://src:oldpw@dokku-shared-redis:6379/0")
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

      it "re-flips REDIS_URL back to the captured pre-cutover URL, destroys dedicated, leaves shared running" do
        expect { described_class.new.perform(dedicated.id) }.to raise_error(Lifecycle::Ops::Timeout)

        expect(app.env_vars.find_by(key: "REDIS_URL")&.value).to eq("redis://src:oldpw@dokku-shared-redis:6379/0")
        expect(DatabaseService.exists?(dedicated.id)).to eq(false)
        expect(shared.reload.status).to eq("running")
        expect(app.app_databases.where(alias_name: "REDIS").map(&:database_service_id)).to eq([ shared.id ])
      end
    end
  end
end

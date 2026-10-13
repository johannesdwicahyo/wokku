require "rails_helper"

RSpec.describe DatabaseServiceUpgrade do
  let(:server) { create(:server) }
  let(:user)   { create(:user) }
  let(:app)    { create(:app_record, creator: user, server: server) }
  let(:parent) do
    DatabaseService.create!(
      server: server, name: "dokku-shared-postgres", service_type: "postgres",
      tier_name: "shared_host", shared: false, status: :running
    )
  end
  let!(:shared) do
    DatabaseService.create!(
      server: server, parent_service: parent, name: "#{app.name}-pg-src",
      service_type: "postgres", tier_name: DatabaseProvisioner::SHARED_TIER,
      shared: true, status: :running, creator: user, live_db_bytes: 50 * 1024 * 1024
    ).tap { |db| AppDatabase.create!(app_record: app, database_service: db, alias_name: "DATABASE") }
  end

  let(:solo) { create(:plan, :solo, dedicated_pg_slots: 3, dedicated_pg_size_mb: 512) }
  before    { allow(user).to receive(:current_plan).and_return(solo) }

  around do |ex|
    orig = ENV["BUNDLE_V2_ENABLED"]
    ENV["BUNDLE_V2_ENABLED"] = "true"
    ex.run
  ensure
    ENV["BUNDLE_V2_ENABLED"] = orig
  end

  describe ".call (postgres engine — default)" do
    it "creates a dedicated DatabaseService row + enqueues the upgrade job" do
      expect {
        described_class.call(app: app, user: user)
      }.to change { DatabaseService.where(service_type: "postgres", shared: false).count }.by(1)
        .and have_enqueued_job(UpgradeSharedPgToDedicatedJob)
    end

    it "marks the new row :upgrading_provisioning with upgrade_source_id set" do
      dedicated = described_class.call(app: app, user: user)
      expect(dedicated.status).to eq("upgrading_provisioning")
      expect(dedicated.upgrade_source_id).to eq(shared.id)
    end

    it "raises NoSharedTenant when the app has no shared Pg" do
      shared.destroy
      expect { described_class.call(app: app, user: user) }
        .to raise_error(UpgradeError::NoSharedTenant)
    end

    it "raises PlanNoSlots on the Free plan" do
      free = create(:plan, :free, dedicated_pg_slots: 0, dedicated_pg_size_mb: 0)
      allow(user).to receive(:current_plan).and_return(free)
      expect { described_class.call(app: app, user: user) }
        .to raise_error(UpgradeError::PlanNoSlots)
    end

    it "raises NoFreeSlots when all dedicated slots are in use" do
      3.times do |i|
        DatabaseService.create!(
          server: server, name: "other-#{i}-pg-dedicated", service_type: "postgres",
          tier_name: "basic", shared: false, status: :running, creator: user
        )
      end
      expect { described_class.call(app: app, user: user) }
        .to raise_error(UpgradeError::NoFreeSlots)
    end

    it "raises ExceedsDedicatedCap when the shared tenant exceeds plan's cap" do
      shared.update!(live_db_bytes: 600 * 1024 * 1024)
      expect { described_class.call(app: app, user: user) }
        .to raise_error(UpgradeError::ExceedsDedicatedCap, /600 MB.*Solo.*512 MB/)
    end
  end

  describe ".call (redis engine)" do
    let(:redis_parent) do
      DatabaseService.create!(
        server: server, name: "dokku-shared-redis", service_type: "redis",
        tier_name: "shared_host", shared: false, status: :running
      )
    end
    let!(:shared_redis) do
      DatabaseService.create!(
        server: server, parent_service: redis_parent, name: "#{app.name}-redis-src",
        service_type: "redis", tier_name: DatabaseProvisioner::SHARED_TIER,
        shared: true, status: :running, creator: user, live_db_bytes: 10 * 1024 * 1024
      ).tap { |db| AppDatabase.create!(app_record: app, database_service: db, alias_name: "REDIS") }
    end

    let(:solo_with_redis) do
      create(:plan, :solo,
             dedicated_pg_slots: 3, dedicated_pg_size_mb: 512,
             dedicated_redis_slots: 3, dedicated_redis_size_mb: 128)
    end
    before { allow(user).to receive(:current_plan).and_return(solo_with_redis) }

    it "creates a dedicated redis DatabaseService row + enqueues UpgradeSharedRedisToDedicatedJob" do
      expect {
        described_class.call(app: app, user: user, engine: "redis")
      }.to change { DatabaseService.where(service_type: "redis", shared: false).count }.by(1)
        .and have_enqueued_job(UpgradeSharedRedisToDedicatedJob)
    end

    it "raises NoFreeSlots when all dedicated redis slots are in use" do
      3.times do |i|
        DatabaseService.create!(
          server: server, name: "other-#{i}-redis-dedicated", service_type: "redis",
          tier_name: "basic", shared: false, status: :running, creator: user
        )
      end
      expect { described_class.call(app: app, user: user, engine: "redis") }
        .to raise_error(UpgradeError::NoFreeSlots)
    end

    it "raises NoSharedTenant when the app has no shared Redis" do
      shared_redis.destroy
      expect { described_class.call(app: app, user: user, engine: "redis") }
        .to raise_error(UpgradeError::NoSharedTenant)
    end
  end

  describe ".call (mongodb — fresh-create, no shared variant)" do
    # Bundle v2 REVISED 2026-05-31: MySQL + Mongo are dedicated-only.
    # No shared tenant exists. Pre-flight skips the shared check. All 3
    # DB engines (postgres/mysql/mongodb) share one plan slot pool
    # (dedicated_pg_slots) — mysql is retired for NEW rows (see
    # database_service.rb RETIRED_TYPES) but existing rows still count
    # against the pool, see "counts all 3 DB engines..." below. mongodb
    # is the only living fresh-create-only engine, so it's the sole
    # example for the create-path examples.
    let(:solo_db) { create(:plan, :solo, dedicated_pg_slots: 3, dedicated_pg_size_mb: 1024) }
    before        { allow(user).to receive(:current_plan).and_return(solo_db) }

    context "for mongodb" do
      it "creates a dedicated DatabaseService row + enqueues CreateDedicatedDatabaseJob" do
        expect {
          described_class.call(app: app, user: user, engine: "mongodb")
        }.to change { DatabaseService.where(service_type: "mongodb", shared: false).count }.by(1)
          .and have_enqueued_job(CreateDedicatedDatabaseJob)
      end

      it "does NOT check for a shared tenant" do
        expect { described_class.call(app: app, user: user, engine: "mongodb") }.not_to raise_error
      end

      it "leaves upgrade_source_id nil (fresh-create has no source)" do
        dedicated = described_class.call(app: app, user: user, engine: "mongodb")
        expect(dedicated.upgrade_source_id).to be_nil
      end
    end

    it "counts all 3 DB engines against the same slot pool" do
      DatabaseService.create!(server: server, name: "x-pg",    service_type: "postgres", tier_name: "basic", shared: false, status: :running, creator: user)
      mysql = DatabaseService.create!(server: server, name: "x-mysql", service_type: "postgres", tier_name: "basic", shared: false, status: :running, creator: user)
      mysql.update_column(:service_type, "mysql") # grandfathered pre-retirement row
      DatabaseService.create!(server: server, name: "x-mongo", service_type: "mongodb", tier_name: "basic", shared: false, status: :running, creator: user)

      expect { described_class.call(app: app, user: user, engine: "mongodb") }
        .to raise_error(UpgradeError::NoFreeSlots)
    end

    it "counts mariadb against the same DB slot pool as postgres/mysql/mongodb" do
      expect(described_class::DB_ENGINES_POOL).to contain_exactly("postgres", "mysql", "mariadb", "mongodb")
    end

    it "for mariadb creates a dedicated DatabaseService row + enqueues CreateDedicatedDatabaseJob" do
      expect {
        described_class.call(app: app, user: user, engine: "mariadb")
      }.to change { DatabaseService.where(service_type: "mariadb", shared: false).count }.by(1)
        .and have_enqueued_job(CreateDedicatedDatabaseJob)
    end

    it "for mariadb with a shared tenant MIGRATES it (not a fresh empty DB) and enforces the size cap" do
      maria_parent = DatabaseService.create!(server: server, name: "dokku-shared-mariadb", service_type: "mariadb",
                                             tier_name: "shared_host", shared: false, status: :running)
      maria = DatabaseService.create!(server: server, parent_service: maria_parent, name: "#{app.name}-mariadb-shared-abc",
                                      service_type: "mariadb", tier_name: DatabaseProvisioner::SHARED_TIER, shared: true,
                                      status: :running, creator: user, live_db_bytes: 10.megabytes)
      AppDatabase.create!(app_record: app, database_service: maria, alias_name: "MARIADB")

      dedicated = nil
      expect { dedicated = described_class.call(app: app, user: user, engine: "mariadb") }
        .to have_enqueued_job(UpgradeSharedPgToDedicatedJob)
      expect(dedicated.upgrade_source).to eq(maria)

      maria.update_column(:live_db_bytes, 2.gigabytes) # over solo_db cap (1024 MB)
      dedicated.destroy!
      expect { described_class.call(app: app, user: user, engine: "mariadb") }
        .to raise_error(UpgradeError::ExceedsDedicatedCap)
    end

    it "size follows box_size, not plan cap" do
      app.update!(box_size: "medium")
      dedicated = described_class.call(app: app, user: user, engine: "mongodb")
      expect(dedicated.tier_name).to eq("standard")
    end

    it "defaults to basic tier when box_size is nil" do
      app.update!(box_size: nil)
      dedicated = described_class.call(app: app, user: user, engine: "mongodb")
      expect(dedicated.tier_name).to eq("basic")
    end
  end

  describe "feature flag" do
    around do |ex|
      orig = ENV["BUNDLE_V2_ENABLED"]
      ex.run
    ensure
      ENV["BUNDLE_V2_ENABLED"] = orig
    end

    it "raises PlanNoSlots when BUNDLE_V2_ENABLED is off, regardless of plan" do
      ENV["BUNDLE_V2_ENABLED"] = "false"
      expect { described_class.call(app: app, user: user) }
        .to raise_error(UpgradeError::PlanNoSlots)
    end
  end

  # Per-resource launch blocker (fix round 1): builder mode must create a
  # shaped row, gated by the builder's enforcer before anything exists.
  describe "per-resource builder" do
    before { ServiceTier.create!(service_type: "postgres", name: "basic", spec: { "memory_mb" => 512, "storage_gb" => 5 }) }

    it "creates a shaped row from the tier spec when the builder is on" do
      allow(Wokku.config).to receive(:resource_builder?).and_return(true)
      dedicated = described_class.call(app: app, user: user)
      expect(dedicated.tier_name).to eq("basic")
      expect(dedicated.shape.to_h).to eq(cpu: 0.25, memory_mb: 512, disk_gb: 5)
    end

    it "keeps a tier-only row when the builder is off" do
      allow(Wokku.config).to receive(:resource_builder?).and_return(false)
      dedicated = described_class.call(app: app, user: user)
      expect([ dedicated.tier_name, dedicated.cpu, dedicated.memory_mb, dedicated.disk_gb ]).to eq([ "basic", nil, nil, nil ])
    end

    it "refuses over the account limit before creating anything" do
      allow(Wokku.config).to receive(:resource_builder?).and_return(true)
      allow(Wokku.config.plan_enforcer).to receive(:allowed?).and_return(false)
      before_count = DatabaseService.where(shared: false).count
      expect {
        expect { described_class.call(app: app, user: user) }
          .to raise_error(UpgradeError::OverLimit, /over your account limit/)
      }.not_to have_enqueued_job(UpgradeSharedPgToDedicatedJob)
      expect(DatabaseService.where(shared: false).count).to eq(before_count)
    end
  end
end

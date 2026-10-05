# frozen_string_literal: true

require "rails_helper"

# Coverage variant — exercises #call (both branches), the destroy! class
# methods, and the shared-tenant teardown. All provisioning AND teardown go
# through wokkud ops (W7 Phase 3: the shared-tenant destroy rides a
# tenant.destroy op on the parent — the SSH leg is gone).
RSpec.describe DatabaseProvisioner do
  let(:server) { create(:server) }
  let(:app)    { create(:app_record, server: server) }

  let(:succeeded_op) { build_stubbed(:service_op, status: :succeeded) }

  describe "#call — dedicated path" do
    before { allow(Services::Ops).to receive(:issue_and_wait!).and_return(succeeded_op) }

    it "creates a DatabaseService via a service.create op and links it to the app" do
      db = nil
      expect {
        db = described_class.new(app: app, service_type: "postgres", tier: "basic").call
      }.to change { DatabaseService.count }.by(1)
        .and change { AppDatabase.count }.by(1)

      expect(Services::Ops).to have_received(:issue_and_wait!)
        .with(hash_including(kind: "service.create"))
      expect(db.shared?).to be(false)
      expect(db.wokkud_managed).to be(true)
      expect(db.tier_name).to eq("basic")
      expect(db.status).to eq("running")
      expect(db.creator).to eq(app.creator)
      expect(db.name).to eq("#{app.name}-postgres")
    end

    # LATENT BUG: the constructor documents `app: nil` for unlinked API
    # provisioning, but @server is derived solely from app&.server and there
    # is no server: param. DatabaseService belongs_to :server (required), so
    # the unlinked dedicated path raises a validation error in practice.
    it "raises (server required) on the unlinked app:nil dedicated path" do
      expect {
        described_class.new(app: nil, service_type: "postgres").call
      }.to raise_error(ActiveRecord::RecordInvalid, /Server/)
    end

    it "honours an explicit name when given" do
      db = described_class.new(
        app: app, service_type: "postgres", name: "custom-db"
      ).call
      expect(db.name).to eq("custom-db")
    end

    it "defaults a blank tier to DEFAULT_TIER" do
      db = described_class.new(app: app, service_type: "postgres", tier: "").call
      expect(db.tier_name).to eq("basic")
    end

    it "routes mongodb + shared_free to the dedicated path (shared? is postgres/mariadb-only)" do
      db = described_class.new(
        app: app, service_type: "mongodb", tier: "shared_free"
      ).call
      expect(db.shared?).to be(false)
      expect(Services::Ops).to have_received(:issue_and_wait!)
        .with(hash_including(kind: "service.create"))
    end
  end

  describe "#call — shared path" do
    # W7 Phase 3: the overlay-ensure leg requires a wokkud-managed parent for
    # EVERY app (all apps run as Swarm tasks) — seed it up front the way prod
    # servers carry their adopted parents.
    let!(:parent) do
      DatabaseService.create!(server: server, name: "dokku-shared-postgres",
                              service_type: "postgres", status: :running,
                              tier_name: "shared_host", shared: false, wokkud_managed: true)
    end

    before { allow(Services::Ops).to receive(:issue_and_wait!).and_return(succeeded_op) }

    it "provisions a tenant via a tenant.provision op, creates a tenant row, and sets DATABASE_URL" do
      db = nil
      expect {
        db = described_class.new(
          app: app, service_type: "postgres", tier: "shared_free"
        ).call
      }.to change { DatabaseService.count }.by(1) # tenant (parent pre-seeded)

      expect(Services::Ops).to have_received(:issue_and_wait!)
        .with(hash_including(kind: "tenant.provision"))
      expect(db.shared?).to be(true)
      expect(db.tier_name).to eq("shared_free")
      expect(db.shared_role_name).to eq("#{app.name}_role")
      expect(db.shared_db_name).to eq(app.name)
      expect(db.parent_service).to eq(parent)
      # cp env truth (B6): DSN persisted as an EnvVar row, no dokku mirror.
      expect(app.env_vars.find_by(key: "DATABASE_URL")).to be_present
      # quota resolves from creator's plan db_bundle_mb (or the shared
      # default when the creator has no plan) — assert a positive integer.
      expect(db.storage_mb_quota).to be_a(Integer).and be_positive
    end

    it "ensures the parent joins the wokku-services overlay via service.ensure (the DSN host's network)" do
      described_class.new(app: app, service_type: "postgres", tier: "shared_free").call

      expect(Services::Ops).to have_received(:issue_and_wait!)
        .with(service: parent, kind: "service.ensure", params: {})
    end

    it "raises loudly when the parent is not wokkud-managed" do
      parent.update!(wokkud_managed: false)
      expect {
        described_class.new(app: app, service_type: "postgres", tier: "shared_free").call
      }.to raise_error(DatabaseProvisioner::Error, /not wokkud-managed/)
    end

    it "passes the creator's plan db_bundle_mb as the tenant.provision quota when resolvable" do
      plan = double("plan", db_bundle_mb: 500)
      creator = create(:user)
      allow(creator).to receive(:current_plan).and_return(plan)

      described_class.new(
        app: app, service_type: "postgres", tier: "shared_free", creator: creator
      ).call

      expect(Services::Ops).to have_received(:issue_and_wait!)
        .with(hash_including(kind: "tenant.provision", params: hash_including(quota_mb: 500)))
    end

    it "raises Error when a non-postgres type reaches provision_shared!" do
      provisioner = described_class.new(
        app: app, service_type: "mongodb", tier: "shared_free"
      )
      # bypass the dedicated routing in #call and hit the inner guard directly
      expect {
        provisioner.send(:provision_shared!)
      }.to raise_error(DatabaseProvisioner::Error, /requires a postgres/)
    end

    it "reuses the existing parent record across two provisions" do
      described_class.new(app: app, service_type: "postgres", tier: "shared_free").call
      app2 = create(:app_record, server: server)

      expect {
        described_class.new(app: app2, service_type: "postgres", tier: "shared_free").call
      }.to change { DatabaseService.count }.by(1) # tenant only; parent reused

      parents = DatabaseService.where(name: "dokku-shared-postgres")
      expect(parents.count).to eq(1)
    end
  end

  describe ".destroy!" do
    it "takes the farewell snapshot FIRST, before any teardown (async export needs a committed op + live data)" do
      db = create(:database_service, server: server, service_type: "postgres", shared: false)
      order = []
      allow_any_instance_of(DatabaseService).to receive(:farewell_snapshot!) { order << :farewell }
      allow(Services::Ops).to receive(:issue_and_wait!) { order << :teardown; succeeded_op }

      described_class.destroy!(database_service: db)
      expect(order).to eq([ :farewell, :teardown ])
    end

    it "destroys a dedicated database via a service.destroy op and removes the row" do
      db = create(:database_service, server: server, service_type: "postgres", shared: false)
      expect(Services::Ops).to receive(:issue_and_wait!)
        .with(service: db, kind: "service.destroy", params: { force: true })
        .and_return(succeeded_op)

      expect {
        described_class.destroy!(database_service: db)
      }.to change { DatabaseService.exists?(db.id) }.from(true).to(false)
    end

    it "swallows a dedicated destroy op failure and still removes the row" do
      db = create(:database_service, server: server, service_type: "postgres", shared: false)
      failed_op = build_stubbed(:service_op, status: :failed, error: "already gone")
      allow(Services::Ops).to receive(:issue_and_wait!)
        .and_raise(Services::Ops::Failed.new(failed_op))

      expect {
        described_class.destroy!(database_service: db)
      }.to change { DatabaseService.exists?(db.id) }.from(true).to(false)
    end

    it "routes shared services to destroy_shared_tenant!" do
      parent = DatabaseService.create!(
        server: server, name: "dokku-shared-postgres", service_type: "postgres",
        tier_name: "shared_host", shared: false, status: :running
      )
      db = DatabaseService.create!(
        server: server, parent_service: parent, name: "tenant-pg", service_type: "postgres",
        tier_name: DatabaseProvisioner::SHARED_TIER, shared: true, status: :running,
        shared_role_name: "u_x_role", shared_db_name: "db_x"
      )
      expect(described_class).to receive(:destroy_shared_tenant!).with(db)
      described_class.destroy!(database_service: db)
    end
  end

  describe ".destroy_shared_tenant!" do
    let(:server2) { create(:server) }
    let(:parent) do
      DatabaseService.create!(
        server: server2, name: "dokku-shared-postgres", service_type: "postgres",
        tier_name: "shared_host", shared: false, status: :running, wokkud_managed: true
      )
    end
    let(:db) do
      DatabaseService.create!(
        server: server2, parent_service: parent, name: "tenant-pg", service_type: "postgres",
        tier_name: DatabaseProvisioner::SHARED_TIER, shared: true, status: :running,
        shared_role_name: "myslug_role", shared_db_name: "myslug"
      )
    end

    it "unsets DATABASE_URL per linked app, issues tenant.destroy on the parent, and destroys the row" do
      linked = create(:app_record, server: server2)
      AppDatabase.create!(app_record: linked, database_service: db, alias_name: "DATABASE")

      linked.env_vars.create!(key: "DATABASE_URL", value: "postgres://old")

      expect(Services::Ops).to receive(:issue_and_wait!)
        .with(service: parent, kind: "tenant.destroy", params: { slug: "myslug", force: true })
        .and_return(succeeded_op)

      expect {
        described_class.destroy_shared_tenant!(db)
      }.to change { DatabaseService.exists?(db.id) }.from(true).to(false)
      # cp env truth (B6): the unset is an EnvVar destroy, no dokku mirror.
      expect(linked.env_vars.where(key: "DATABASE_URL")).to be_empty
    end

    it "unsets the engine's own env keys for a non-postgres shared tenant (redis)" do
      redis_parent = DatabaseService.create!(
        server: server2, name: "dokku-shared-redis", service_type: "redis",
        tier_name: "shared_host", shared: false, status: :running, wokkud_managed: true
      )
      redis_db = DatabaseService.create!(
        server: server2, parent_service: redis_parent, name: "tenant-redis", service_type: "redis",
        tier_name: DatabaseProvisioner::SHARED_TIER, shared: true, status: :running,
        shared_role_name: "myslug", shared_db_name: "myslug"
      )
      linked = create(:app_record, server: server2)
      AppDatabase.create!(app_record: linked, database_service: redis_db, alias_name: "REDIS")
      linked.env_vars.create!(key: "REDIS_URL", value: "redis://old")
      linked.env_vars.create!(key: "DATABASE_URL", value: "postgres://keep-me")

      expect(Services::Ops).to receive(:issue_and_wait!)
        .with(service: redis_parent, kind: "tenant.destroy", params: { slug: "myslug", force: true })
        .and_return(succeeded_op)

      described_class.destroy_shared_tenant!(redis_db)

      expect(linked.env_vars.where(key: "REDIS_URL")).to be_empty
      # Destroying a redis tenant must NOT nuke the app's postgres URL
      # (the old teardown unset DATABASE_URL for every shared engine).
      expect(linked.env_vars.find_by(key: "DATABASE_URL").value).to eq("postgres://keep-me")
    end

    it "swallows unset + tenant.destroy errors and still destroys the row" do
      linked = create(:app_record, server: server2)
      AppDatabase.create!(app_record: linked, database_service: db, alias_name: "DATABASE")

      allow(Apps::EnvWriter).to receive(:unset).and_raise(StandardError, "unset boom")
      allow(Services::Ops).to receive(:issue_and_wait!).and_raise(Services::Ops::Timeout, "drop boom")

      expect {
        described_class.destroy_shared_tenant!(db)
      }.to change { DatabaseService.exists?(db.id) }.from(true).to(false)
    end

    it "skips the host teardown (row still destroyed) when no parent row remains" do
      db.update_column(:parent_service_id, nil) # orphan row — bypasses the shared-needs-parent validation
      expect(Services::Ops).not_to receive(:issue_and_wait!)

      expect {
        described_class.destroy_shared_tenant!(db)
      }.to change { DatabaseService.exists?(db.id) }.from(true).to(false)
    end
  end

  describe ".shared_tenant_slug" do
    it "prefers shared_db_name, then the de-suffixed role name, then the row-name convention" do
      expect(described_class.shared_tenant_slug(
        build(:database_service, shared_db_name: "slug_a", shared_role_name: "slug_b_role", name: "x")
      )).to eq("slug_a")
      expect(described_class.shared_tenant_slug(
        build(:database_service, shared_db_name: nil, shared_role_name: "slug_b_role", name: "x")
      )).to eq("slug_b")
      expect(described_class.shared_tenant_slug(
        build(:database_service, service_type: "memcached", shared_db_name: nil, shared_role_name: nil,
                                 name: "myapp-memcached-shared-a1b2c3")
      )).to eq("myapp")
      expect(described_class.shared_tenant_slug(
        build(:database_service, service_type: "postgres", shared_db_name: nil, shared_role_name: nil,
                                 name: "myapp-pg-shared-a1b2c3")
      )).to eq("myapp")
    end
  end
end

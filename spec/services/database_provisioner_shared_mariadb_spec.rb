# frozen_string_literal: true

require "rails_helper"

# Shared MariaDB (free, 2026-10-05) mirrors the shared-postgres path:
# tenant.provision on a per-server parent, quota = plan.db_bundle_mb on the
# tenant row (swept by SharedDatabaseQuotaJob). Differences pinned here: the
# parent row is born wokkud-managed and ensured BEFORE the tenant op (wokkud
# creates the container on first ensure), and DATABASE_URL is only claimed
# when the app has none.
RSpec.describe DatabaseProvisioner, "shared mariadb" do
  let(:server)  { create(:server) }
  let(:creator) { create(:user) }
  let(:app)     { create(:app_record, name: "shop", server: server, creator: creator) }
  let(:plan)    { double("plan", db_bundle_mb: 1024) }
  let(:calls)   { [] }

  before do
    allow(creator).to receive(:current_plan).and_return(plan)
    allow(SecureRandom).to receive(:hex).and_call_original
    allow(SecureRandom).to receive(:hex).with(16).and_return("s3cret")
    allow(Services::Ops).to receive(:issue_and_wait!) do |service:, kind:, params: {}, **|
      calls << [ service.name, kind, params ]
      build_stubbed(:service_op, status: :succeeded)
    end
  end

  def provision(app: self.app)
    described_class.new(app: app, service_type: "mariadb", tier: "shared_free", creator: creator).call
  end

  it "births the parent row wokkud-managed and ensures it BEFORE tenant.provision" do
    db = provision
    parent = db.parent_service

    expect(parent).to have_attributes(name: "dokku-shared-mariadb", service_type: "mariadb",
                                      tier_name: "shared_host", shared: false, wokkud_managed: true)
    kinds = calls.map { |name, kind, _| [ name, kind ] }
    expect(kinds.first(2)).to eq([ [ "dokku-shared-mariadb", "service.ensure" ],
                                   [ "dokku-shared-mariadb", "tenant.provision" ] ])
  end

  it "provisions with quota = plan.db_bundle_mb and 40 connections, stamping the quota on the tenant row" do
    db = provision

    expect(calls).to include([ "dokku-shared-mariadb", "tenant.provision",
                               { slug: "shop", password: "s3cret", quota_mb: 1024, max_connections: 40 } ])
    expect(db).to have_attributes(service_type: "mariadb", shared: true, tier_name: "shared_free",
                                  shared_db_name: "shop", shared_role_name: "shop",
                                  storage_mb_quota: 1024, wokkud_managed: true,
                                  dsn: "mysql://shop:s3cret@dokku-shared-mariadb:3306/shop")
    expect(db.name).to match(/\Ashop-mariadb-shared-\h{6}\z/)
    expect(described_class.shared_tenant_slug(db)).to eq("shop")
    expect(creator.current_plan.db_bundle_mb).to eq(db.storage_mb_quota)
  end

  it "sets MARIADB_URL (dedicated naming) + DATABASE_URL (mysql2) and links under the MARIADB alias" do
    db = provision

    envs = app.env_vars.pluck(:key, :value).to_h
    expect(envs).to include("MARIADB_URL" => "mysql://shop:s3cret@dokku-shared-mariadb:3306/shop",
                            "DATABASE_URL" => "mysql2://shop:s3cret@dokku-shared-mariadb:3306/shop")
    expect(app.app_databases.find_by(database_service: db).alias_name).to eq("MARIADB")
  end

  it "leaves an existing DATABASE_URL (e.g. a shared postgres tenant) alone" do
    Apps::EnvWriter.set(app, { "DATABASE_URL" => "postgres://pg" })

    provision

    expect(app.env_vars.find_by(key: "DATABASE_URL").value).to eq("postgres://pg")
    expect(app.env_vars.find_by(key: "MARIADB_URL")).to be_present
  end

  it "reuses one parent row per server" do
    provision
    provision(app: create(:app_record, name: "shop2", server: server, creator: creator))

    expect(DatabaseService.where(server: server, name: "dokku-shared-mariadb").count).to eq(1)
  end

  describe ".destroy!" do
    let!(:db) { provision }

    before { allow(db).to receive(:farewell_snapshot!) }

    it "drops the tenant on the parent and unsets its env (DATABASE_URL only when it is ours)" do
      calls.clear
      described_class.destroy!(database_service: db)

      expect(calls).to include([ "dokku-shared-mariadb", "tenant.destroy", { slug: "shop", force: true } ])
      expect(app.env_vars.where(key: %w[MARIADB_URL DATABASE_URL])).to be_empty
      expect(DatabaseService.exists?(db.id)).to be(false)
    end

    it "keeps a DATABASE_URL that belongs to someone else" do
      Apps::EnvWriter.set(app, { "DATABASE_URL" => "postgres://pg" })

      described_class.destroy!(database_service: db)

      expect(app.env_vars.find_by(key: "DATABASE_URL").value).to eq("postgres://pg")
      expect(app.env_vars.find_by(key: "MARIADB_URL")).to be_nil
    end
  end

  it "is reached from Addons::SharedProvisioner for engine mariadb" do
    allow(Addons::SharedProvisioner).to receive(:feature_enabled?).and_return(true)

    expect(Addons::SharedProvisioner.new(app: app, engine: "mariadb").call).to eq(:provisioned)
    expect(app.database_services.where(service_type: "mariadb", shared: true, status: :running)).to exist
    expect(Addons::SharedProvisioner.new(app: app, engine: "mariadb").call).to eq(:already_attached)
  end
end

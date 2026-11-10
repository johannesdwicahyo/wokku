# frozen_string_literal: true

require "rails_helper"

RSpec.describe DatabaseProvisioner do
  let(:app) { app_records(:one) }

  it "shared_free tier is postgres-only (mongodb falls through to dedicated)" do
    op = build_stubbed(:service_op, status: :succeeded)
    allow(Services::Ops).to receive(:issue_and_wait!).and_return(op)

    provisioner = described_class.new(app: app, service_type: "mongodb", tier: "shared_free")
    db = provisioner.call
    expect(db.shared?).to be_falsey
    expect(Services::Ops).to have_received(:issue_and_wait!)
      .with(hash_including(kind: "service.create"))
  end

  describe "wokkud service-ops branching (Phase B4)" do
    describe "#provision_dedicated!" do
      context "when the server has wokkud services enabled" do
        before { app.server.update!(wokkud_services_enabled: true) }

        it "links the row to the app before the op, so a failed create is never an unlinked orphan" do
          allow(Services::Ops).to receive(:issue_and_wait!).and_raise(Services::Ops::Timeout, "agent never reported")

          expect {
            described_class.new(app: app, service_type: "postgres", tier: "mini", name: "orphan-check-postgres").call
          }.to raise_error(Services::Ops::Timeout)

          expect(app.reload.database_services.pluck(:name)).to include("orphan-check-postgres")
        end

        it "provisions via a service.create op, marks wokkud_managed, and never SSHes" do
          op = build_stubbed(:service_op, status: :succeeded)
          expect(Services::Ops).to receive(:issue_and_wait!)
            .with(service: kind_of(DatabaseService), kind: "service.create",
                  params: hash_including(:service_type, :image, :admin_pass, :memory_mb, :max_connections, :network, :volume_path))
            .and_return(op)
          expect(Hosts::Ssh).not_to receive(:new)
          app.env_vars.where(key: "DATABASE_URL").delete_all # fixture ships one

          db = described_class.new(app: app, service_type: "postgres", tier: "mini").call

          expect(db.wokkud_managed).to be(true)
          expect(db.dsn).to be_present
          expect(db.status).to eq("running")
          expect(app.env_vars.find_by(key: "POSTGRES_URL")&.value).to eq(db.dsn)
          expect(app.env_vars.find_by(key: "DATABASE_URL")&.value).to eq(db.dsn)
          # The DSN host (container name) resolves via the wokku-services
          # overlay the service joins at create and every app task runs on —
          # no dokku network attach step remains.
        end

        it "leaves an existing DATABASE_URL alone (a shared tenant or another DB owns it)" do
          allow(Services::Ops).to receive(:issue_and_wait!).and_return(build_stubbed(:service_op, status: :succeeded))
          Apps::EnvWriter.set(app, { "DATABASE_URL" => "postgres://existing/db" }) # explicit, not the fixture's

          db = described_class.new(app: app, service_type: "postgres", tier: "mini").call

          expect(app.env_vars.find_by(key: "POSTGRES_URL")&.value).to eq(db.dsn)
          expect(app.env_vars.find_by(key: "DATABASE_URL")&.value).to eq("postgres://existing/db")
        end

        # Task 10: a fresh dedicated DB must get its APPLICATION database
        # created inside the engine. The db name is the UNDERSCORED
        # dedicated_db_name (the single source of truth backup/restore
        # already use) — the DSN's database segment and the service.create
        # `database:` param must both use it, while the DSN HOST stays the
        # hyphenated container name.
        it "passes the underscored dedicated_db_name as the create database param and DSN database segment (host stays hyphenated)" do
          op = build_stubbed(:service_op, status: :succeeded)
          expect(Services::Ops).to receive(:issue_and_wait!)
            .with(service: kind_of(DatabaseService), kind: "service.create",
                  params: hash_including(database: "foo_bar_mariadb"))
            .and_return(op)

          db = described_class.new(app: app, service_type: "mariadb", tier: "mini", name: "foo-bar-mariadb").call

          expect(db.dsn).to match(%r{@dokku\.mariadb\.foo-bar-mariadb:3306/foo_bar_mariadb\z})
          expect(app.env_vars.find_by(key: "MARIADB_URL")&.value).to eq(db.dsn)
        end

        it "passes no database param for redis (redis has no application database)" do
          op = build_stubbed(:service_op, status: :succeeded)
          expect(Services::Ops).to receive(:issue_and_wait!)
            .with(service: kind_of(DatabaseService), kind: "service.create",
                  params: hash_including(database: ""))
            .and_return(op)

          db = described_class.new(app: app, service_type: "redis", tier: "mini", name: "foo-bar-redis").call

          expect(db.dsn).to end_with(":6379/0")
        end

        # Review fix: DEFAULT_IMAGES.fetch used to raise ArgumentError from
        # INSIDE provision_dedicated_via_ops!, i.e. AFTER DatabaseService.create!
        # had already inserted a row and BEFORE app.app_databases.create! ran —
        # so rollback_partial_deploy! (which iterates app.app_databases) never
        # saw the orphan, and it stayed stuck in status "creating" forever.
        # The check must now be a pre-flight guard that raises before any row
        # is created (elasticsearch: huly/tubearchivist/zincsearch never had a
        # wokkud image mapping).
        it "raises before creating any DatabaseService row for an engine with no wokkud image" do
          expect(Services::Ops).not_to receive(:issue_and_wait!)

          expect {
            described_class.new(app: app, service_type: "elasticsearch", tier: "mini").call
          }.to raise_error(ArgumentError, /elasticsearch is not supported/i)
            .and(change(DatabaseService, :count).by(0))
        end
      end
    end

    describe ".destroy!" do
      context "for a wokkud-managed dedicated service" do
        it "issues a service.destroy op (force: true) instead of SSHing" do
          db = create(:database_service, server: app.server, service_type: "postgres",
                       shared: false, wokkud_managed: true)
          op = build_stubbed(:service_op, status: :succeeded)
          expect(Services::Ops).to receive(:issue_and_wait!)
            .with(service: db, kind: "service.destroy", params: { force: true })
            .and_return(op)
          expect(Hosts::Ssh).not_to receive(:new)

          described_class.destroy!(database_service: db)

          expect(DatabaseService.exists?(db.id)).to be(false)
        end
      end
    end

    describe "#provision_shared! tenant call" do
      let(:parent) do
        DatabaseService.create!(
          name: "dokku-shared-postgres", service_type: "postgres", server: app.server,
          status: :running, tier_name: "shared_host", shared: false
        )
      end

      context "when the shared-postgres parent is wokkud_managed" do
        # Shared tenants set DATABASE_URL only when the app has none (they
        # never clobber a dedicated DB's or the user's own value).
        before do
          parent.update!(wokkud_managed: true)
          app.env_vars.where(key: "DATABASE_URL").delete_all
        end

        it "keeps an app's existing DATABASE_URL instead of overwriting it" do
          parent
          app.env_vars.create!(key: "DATABASE_URL", value: "postgres://user-owned/db")
          allow(Services::Ops).to receive(:issue_and_wait!).and_return(build_stubbed(:service_op, status: :succeeded))

          db = described_class.new(app: app, service_type: "postgres", tier: "shared_free").call

          expect(db.dsn).to be_present
          expect(app.env_vars.find_by(key: "DATABASE_URL").value).to eq("postgres://user-owned/db")
        end

        it "provisions the tenant via a tenant.provision op and ensures the parent on the overlay" do
          # find_or_create_by! inside the provisioner resolves this exact row
          # since name/service_type/server match.
          parent
          op = build_stubbed(:service_op, status: :succeeded)
          allow(Services::Ops).to receive(:issue_and_wait!).and_return(op)
          expect(Hosts::Ssh).not_to receive(:new)

          db = described_class.new(app: app, service_type: "postgres", tier: "shared_free").call

          expect(Services::Ops).to have_received(:issue_and_wait!)
            .with(service: parent, kind: "tenant.provision",
                  params: hash_including(slug: app.name, quota_mb: kind_of(Integer), max_connections: 40))
          # The DSN host is the parent container name — resolvable only on
          # the wokku-services overlay every app task runs on.
          expect(Services::Ops).to have_received(:issue_and_wait!)
            .with(service: parent, kind: "service.ensure", params: {})
          expect(db.shared?).to be(true)
          expect(db.wokkud_managed).to be(true)
          expect(db.shared_role_name).to eq("#{app.name}_role")
          expect(db.shared_db_name).to eq(app.name)
          expect(db.dsn).to be_present
          expect(app.env_vars.find_by(key: "DATABASE_URL")&.value).to eq(db.dsn)
          expect(db.dsn).to match(%r{\Apostgres://#{app.name}_role:})
        end

        it "on tenant_exists, reuses the stored dsn from the existing running child row (no fresh-password DSN)" do
          stored_dsn = "postgres://#{app.name}_role:original-secret@#{DatabaseProvisioner::SHARED_PG_NETWORK}:5432/#{app.name}"
          existing = create(:database_service, server: app.server, service_type: "postgres",
                             shared: true, status: :running, parent_service: parent,
                             shared_role_name: "#{app.name}_role", shared_db_name: app.name,
                             wokkud_managed: true, dsn: stored_dsn)

          failed_op = build_stubbed(:service_op, status: :failed, error_code: "tenant_exists")
          ensure_op = build_stubbed(:service_op, status: :succeeded)
          allow(Services::Ops).to receive(:issue_and_wait!) do |kind:, **|
            raise Services::Ops::Failed, failed_op if kind == "tenant.provision"
            ensure_op
          end

          db = described_class.new(app: app, service_type: "postgres", tier: "shared_free").call

          expect(db.dsn).to eq(stored_dsn)
          expect(app.env_vars.find_by(key: "DATABASE_URL")&.value).to eq(stored_dsn)
          expect(existing.reload.dsn).to eq(stored_dsn)
        end

        it "on tenant_exists with no reusable existing row, raises instead of composing a fresh-password DSN" do
          op = build_stubbed(:service_op, status: :failed, error_code: "tenant_exists")
          allow(Services::Ops).to receive(:issue_and_wait!)
            .and_raise(Services::Ops::Failed.new(op))

          expect {
            described_class.new(app: app, service_type: "postgres", tier: "shared_free").call
          }.to raise_error(DatabaseProvisioner::Error, /tenant_exists/)
        end

        it "re-raises a Failed op for any other error_code" do
          op = build_stubbed(:service_op, status: :failed, error_code: "boom")
          allow(Services::Ops).to receive(:issue_and_wait!)
            .and_raise(Services::Ops::Failed.new(op))

          expect {
            described_class.new(app: app, service_type: "postgres", tier: "shared_free").call
          }.to raise_error(Services::Ops::Failed)
        end

        # Record-first: a failed tenant op leaves the row LINKED (so app
        # deletion cleans it up) and marked error, not an unlinked orphan.
        it "links the row to the app before the tenant op and marks it error when the op fails" do
          parent
          allow(Services::Ops).to receive(:issue_and_wait!).and_raise(Services::Ops::Timeout, "agent never reported")

          expect {
            described_class.new(app: app, service_type: "postgres", tier: "shared_free").call
          }.to raise_error(Services::Ops::Timeout)

          db = app.reload.database_services.find_by(shared: true, parent_service: parent)
          expect(db).to be_present
          expect(db.status).to eq("error")
        end
      end
    end
  end

  describe ".image_for" do
    it "uses the tier spec image (pgvector flavour) over the stock default" do
      ServiceTier.find_or_create_by!(name: "basic-pgvector", service_type: "postgres") do |t|
        t.monthly_price_cents = 100
        t.spec = { "image" => "pgvector/pgvector", "image_version" => "pg16" }
      end
      db = create(:database_service, tier_name: "basic-pgvector")
      expect(described_class.image_for(db)).to eq("pgvector/pgvector:pg16")
    end

    it "falls back to DEFAULT_IMAGES when the tier pins no image" do
      db = create(:database_service, tier_name: "basic")
      expect(described_class.image_for(db)).to eq("postgres:16")
    end

    # The live Ghost DBs run mysql:9.6.0 and DatastoreReconcileJob recreates with
    # this image — anything older refuses to start on their data (2026-11-03).
    it "never pins mysql below the 9.6 the live databases run" do
      expect(Gem::Version.new(described_class::DEFAULT_IMAGES["mysql"].split(":").last)).to be >= Gem::Version.new("9.6.0")
      expect(CreateDedicatedDatabaseJob::DEFAULT_IMAGES["mysql"]).to eq(described_class::DEFAULT_IMAGES["mysql"])
    end

    it "raises the friendly refusal for unsupported engines" do
      db = build(:database_service, service_type: "clickhouse", tier_name: "basic")
      expect { described_class.image_for(db) }.to raise_error(ArgumentError, /not supported/)
    end

    it "ensure_params_for recreates with the tier image — supervision must not boot pgvector data on stock postgres" do
      ServiceTier.find_or_create_by!(name: "basic-pgvector", service_type: "postgres") do |t|
        t.monthly_price_cents = 100
        t.spec = { "image" => "pgvector/pgvector", "image_version" => "pg16" }
      end
      db = create(:database_service, tier_name: "basic-pgvector")
      expect(described_class.ensure_params_for(db)[:image]).to eq("pgvector/pgvector:pg16")
    end
  end
end

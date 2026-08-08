require "rails_helper"

RSpec.describe Addons::SharedProvisioner do
  let(:user)   { create(:user) }
  let(:server) { create(:server) }
  let(:app)    { create(:app_record, name: "myapp", creator: user, server: server) }

  describe ".feature_enabled?" do
    around do |ex|
      orig = ENV["BUNDLE_V2_ENABLED"]
      ex.run
    ensure
      ENV["BUNDLE_V2_ENABLED"] = orig
    end

    it "is false when env var unset" do
      ENV["BUNDLE_V2_ENABLED"] = nil
      expect(described_class.feature_enabled?).to eq(false)
    end

    it "is true when set to 'true'" do
      ENV["BUNDLE_V2_ENABLED"] = "true"
      expect(described_class.feature_enabled?).to eq(true)
    end

    it "is true for any truthy alias (1/yes/on)" do
      %w[1 yes on TRUE].each do |v|
        ENV["BUNDLE_V2_ENABLED"] = v
        expect(described_class.feature_enabled?).to eq(true), "alias #{v.inspect} should be truthy"
      end
    end
  end

  describe "#call" do
    let(:service) { described_class.new(app: app, engine: "postgres") }

    around do |ex|
      orig = ENV["BUNDLE_V2_ENABLED"]
      ENV["BUNDLE_V2_ENABLED"] = "true"
      ex.run
    ensure
      ENV["BUNDLE_V2_ENABLED"] = orig
    end

    it "returns :feature_disabled when the flag is off" do
      ENV["BUNDLE_V2_ENABLED"] = "false"
      expect(service.call).to eq(:feature_disabled)
    end

    it "returns :unsupported for engines outside SUPPORTED_ENGINES" do
      result = described_class.new(app: app, engine: "kafka").call
      expect(result).to eq(:unsupported)
    end

    it "returns :missing_server when the app has no server attached" do
      orphan = build(:app_record, creator: user, server: nil)
      allow(orphan).to receive(:server).and_return(nil)
      expect(described_class.new(app: orphan, engine: "postgres").call).to eq(:missing_server)
    end

    it "returns :already_attached when a shared Pg tenant already exists" do
      parent = DatabaseService.create!(
        name: "dokku-shared-postgres", service_type: "postgres", server: server,
        status: :running, tier_name: "shared_free", shared: false
      )
      DatabaseService.create!(
        name: "#{app.name}-pg-shared-x", service_type: "postgres", server: server,
        status: :running, tier_name: "shared_free", shared: true,
        parent_service: parent, creator: user
      ).app_databases.create!(app_record: app, alias_name: "DATABASE")

      expect(service.call).to eq(:already_attached)
    end

    it "delegates to DatabaseProvisioner with shared tier when none attached" do
      provisioner = instance_double(DatabaseProvisioner)
      expect(DatabaseProvisioner).to receive(:new).with(
        hash_including(app: app, service_type: "postgres", tier: DatabaseProvisioner::SHARED_TIER, creator: user)
      ).and_return(provisioner)
      expect(provisioner).to receive(:call)

      expect(service.call).to eq(:provisioned)
    end

    describe "generic engine path (redis/memcached/rabbitmq/meilisearch)" do
      # Byte pins for the CP-composed env shapes: same scheme/host/port form
      # the dokku-shared-* plugins emitted, host = parent container name.
      # slug = app name ("myapp"); meilisearch's key comes from op.result.
      {
        "redis" => {
          alias_env: "REDIS", password_sent: true, result: { "slug" => "myapp" },
          envs: { "REDIS_URL" => "redis://myapp:s3cret@dokku-shared-redis:6379/0" },
          role: "myapp"
        },
        "memcached" => {
          alias_env: "MEMCACHED", password_sent: false, result: { "slug" => "myapp" },
          envs: { "MEMCACHED_URL" => "dokku-shared-memcached:11211", "MEMCACHED_KEY_PREFIX" => "myapp:" },
          role: nil
        },
        "rabbitmq" => {
          alias_env: "RABBITMQ", password_sent: true, result: { "slug" => "myapp" },
          envs: { "RABBITMQ_URL" => "amqp://myapp:s3cret@dokku-shared-rabbitmq:5672/myapp" },
          role: "myapp"
        },
        "meilisearch" => {
          alias_env: "MEILISEARCH", password_sent: false,
          result: { "slug" => "myapp", "api_key" => "meili-rw-key", "api_key_ro" => "meili-ro-key" },
          envs: { "MEILISEARCH_URL" => "http://dokku-shared-meilisearch:7700", "MEILISEARCH_API_KEY" => "meili-rw-key" },
          role: nil
        }
      }.each do |engine, cfg|
        context "for #{engine}" do
          let!(:parent) do
            DatabaseService.create!(server: server, name: "dokku-shared-#{engine}",
                                    service_type: engine, status: :running,
                                    tier_name: "shared_host", shared: false, wokkud_managed: true)
          end

          before do
            allow(SecureRandom).to receive(:hex).and_call_original
            allow(SecureRandom).to receive(:hex).with(16).and_return("s3cret")
            allow(Services::Ops).to receive(:issue_and_wait!) do |service:, kind:, params:|
              expect(service).to eq(parent)
              double("op", result: kind == "tenant.provision" ? cfg[:result] : {})
            end
          end

          it "issues tenant.provision on the PARENT (slug in params#{cfg[:password_sent] ? ', CP password' : ', no password'})" do
            described_class.new(app: app, engine: engine).call

            expected = { slug: "myapp" }
            expected[:password] = "s3cret" if cfg[:password_sent]
            expect(Services::Ops).to have_received(:issue_and_wait!)
              .with(service: parent, kind: "tenant.provision", params: expected)
          end

          it "ensures the parent joins the wokku-services overlay (the DSN host's only resolvable network)" do
            described_class.new(app: app, engine: engine).call
            expect(Services::Ops).to have_received(:issue_and_wait!)
              .with(service: parent, kind: "service.ensure", params: {})
          end

          it "creates a shared DatabaseService row + sets plugin-shape envs + creates app_database alias" do
            result = described_class.new(app: app, engine: engine).call

            expect(result).to eq(:provisioned)
            db = app.database_services.where(service_type: engine, shared: true).first
            expect(db).to be_present
            expect(db.tier_name).to eq(DatabaseProvisioner::SHARED_TIER)
            expect(db.parent_service).to eq(parent)
            expect(db.shared_db_name).to eq("myapp")
            expect(db.shared_role_name).to eq(cfg[:role])
            expect(db.dsn).to eq(cfg[:envs].values.first)
            expect(db.wokkud_managed).to be(true)
            expect(app.app_databases.find_by(database_service: db).alias_name).to eq(cfg[:alias_env])
            # cp env truth (B6): envs land as EnvVar rows, no dokku mirror.
            expect(app.env_vars.pluck(:key, :value).to_h).to include(cfg[:envs])
          end

          it "returns :already_attached on re-run (idempotent)" do
            described_class.new(app: app, engine: engine).call
            expect(described_class.new(app: app, engine: engine).call).to eq(:already_attached)
          end

          it "fails loudly (with tenant rollback) when the parent is not wokkud-managed" do
            parent.update!(wokkud_managed: false)

            expect { described_class.new(app: app, engine: engine).call }
              .to raise_error(described_class::UnsupportedEngine, /not wokkud-managed/)
            # Compensating tenant.destroy so a retry's provision starts clean.
            expect(Services::Ops).to have_received(:issue_and_wait!)
              .with(service: parent, kind: "tenant.destroy", params: { slug: "myapp", force: true })
            db = app.database_services.where(service_type: engine, shared: true).first
            expect(db.status).to eq("error")
          end
        end
      end

      context "meilisearch slug transform" do
        let(:app) { create(:app_record, name: "my-app", creator: user, server: server) }
        let!(:parent) do
          DatabaseService.create!(server: server, name: "dokku-shared-meilisearch",
                                  service_type: "meilisearch", status: :running,
                                  tier_name: "shared_host", shared: false, wokkud_managed: true)
        end

        it "underscores hyphens (meilisearch forbids '-' — it is the index separator)" do
          allow(Services::Ops).to receive(:issue_and_wait!)
            .and_return(double("op", result: { "api_key" => "k" }))

          described_class.new(app: app, engine: "meilisearch").call

          expect(Services::Ops).to have_received(:issue_and_wait!)
            .with(service: parent, kind: "tenant.provision", params: { slug: "my_app" })
          db = app.database_services.where(service_type: "meilisearch", shared: true).first
          expect(db.shared_db_name).to eq("my_app")
          # Prefix-shaped like the plugin era; slug is the transformed one.
          expect(app.env_vars.find_by(key: "MEILISEARCH_API_KEY").value).to eq("k")
        end
      end

      context "meilisearch result redaction" do
        let!(:parent) do
          DatabaseService.create!(server: server, name: "dokku-shared-meilisearch",
                                  service_type: "meilisearch", status: :running,
                                  tier_name: "shared_host", shared: false, wokkud_managed: true)
        end

        it "redacts api keys from the persisted op result once the envs hold them" do
          op = ServiceOp.create!(
            database_service: parent, server: server, kind: "tenant.provision",
            params: { slug: app.name }, status: :succeeded,
            result: { "slug" => app.name, "api_key" => "rw-secret", "api_key_ro" => "ro-secret" }
          )
          allow(Services::Ops).to receive(:issue_and_wait!) do |kind:, **|
            kind == "tenant.provision" ? op : double("op", result: {})
          end

          described_class.new(app: app, engine: "meilisearch").call

          expect(op.reload.result["api_key"]).to eq("[REDACTED]")
          expect(op.reload.result["api_key_ro"]).to eq("[REDACTED]")
          expect(op.reload.result["slug"]).to eq(app.name)
          # The live key still reached the app env before redaction.
          expect(app.env_vars.find_by(key: "MEILISEARCH_API_KEY").value).to eq("rw-secret")
        end
      end

      context "failure + retry semantics (redis)" do
        let!(:parent) do
          DatabaseService.create!(server: server, name: "dokku-shared-redis",
                                  service_type: "redis", status: :running,
                                  tier_name: "shared_host", shared: false, wokkud_managed: true)
        end
        let(:ok_op) { double("op", result: { "slug" => "myapp" }) }

        before do
          allow(Services::Ops).to receive(:issue_and_wait!).and_return(ok_op)
        end

        it "creates a visible :creating row + app link before any host call" do
          allow(Services::Ops).to receive(:issue_and_wait!) do |kind:, **|
            if kind == "tenant.provision"
              db = app.database_services.where(service_type: "redis", shared: true).first
              expect(db).to be_present
              expect(db.status).to eq("creating")
              expect(app.app_databases.find_by(database_service: db)).to be_present
            end
            ok_op
          end
          described_class.new(app: app, engine: "redis").call
        end

        it "marks the row :error, compensates the tenant, and re-raises when a host step fails" do
          allow(Services::Ops).to receive(:issue_and_wait!) do |kind:, **|
            raise Services::Ops::Timeout, "ensure boom" if kind == "service.ensure"
            ok_op
          end

          expect { described_class.new(app: app, engine: "redis").call }
            .to raise_error(Services::Ops::Timeout, /ensure boom/)

          db = app.database_services.where(service_type: "redis", shared: true).first
          expect(db.status).to eq("error")
          expect(Services::Ops).to have_received(:issue_and_wait!)
            .with(service: parent, kind: "tenant.destroy", params: { slug: "myapp", force: true })
        end

        it "rolls back the :creating row if the app link write fails (no orphan)" do
          allow_any_instance_of(ActiveRecord::Associations::CollectionProxy)
            .to receive(:find_or_create_by!)
            .and_raise(ActiveRecord::RecordInvalid.new(AppDatabase.new))

          expect { described_class.new(app: app, engine: "redis").call }
            .to raise_error(ActiveRecord::RecordInvalid)

          expect(DatabaseService.where(service_type: "redis", shared: true).count).to eq(0)
        end

        it "reuses the same :error row on retry (no duplicate) and re-runs provisioning" do
          calls = 0
          allow(Services::Ops).to receive(:issue_and_wait!) do |kind:, **|
            calls += 1 if kind == "service.ensure"
            raise Services::Ops::Timeout, "boom" if kind == "service.ensure" && calls == 1
            ok_op
          end
          expect { described_class.new(app: app, engine: "redis").call }.to raise_error(Services::Ops::Timeout)
          first_id = app.database_services.where(service_type: "redis", shared: true).first.id

          result = described_class.new(app: app, engine: "redis").call

          expect(result).to eq(:provisioned)
          rows = app.database_services.where(service_type: "redis", shared: true)
          expect(rows.count).to eq(1)
          expect(rows.first.id).to eq(first_id)
          expect(rows.first.status).to eq("running")
        end

        it "recycles a leftover host tenant on tenant_exists (destroy + fresh provision)" do
          failed_op = build_stubbed(:service_op, status: :failed, error_code: "tenant_exists")
          provisions = 0
          allow(Services::Ops).to receive(:issue_and_wait!) do |kind:, **|
            if kind == "tenant.provision"
              provisions += 1
              raise Services::Ops::Failed, failed_op if provisions == 1
            end
            ok_op
          end

          expect(described_class.new(app: app, engine: "redis").call).to eq(:provisioned)

          expect(Services::Ops).to have_received(:issue_and_wait!)
            .with(service: parent, kind: "tenant.destroy", params: { slug: "myapp", force: true })
          expect(provisions).to eq(2)
        end

        it "re-raises a Failed op with any other error_code" do
          failed_op = build_stubbed(:service_op, status: :failed, error_code: "boom")
          allow(Services::Ops).to receive(:issue_and_wait!) do |kind:, **|
            raise Services::Ops::Failed, failed_op if kind == "tenant.provision"
            ok_op
          end

          expect { described_class.new(app: app, engine: "redis").call }
            .to raise_error(Services::Ops::Failed)
        end
      end
    end
  end

  describe "#already_attached? semantics" do
    around do |ex|
      orig = ENV["BUNDLE_V2_ENABLED"]
      ENV["BUNDLE_V2_ENABLED"] = "true"
      ex.run
    ensure
      ENV["BUNDLE_V2_ENABLED"] = orig
    end

    it "does NOT treat a :creating or :error shared row as already attached" do
      parent = DatabaseService.create!(
        name: "dokku-shared-redis", service_type: "redis", server: server,
        status: :running, tier_name: "shared_host", shared: false
      )
      db = DatabaseService.create!(
        name: "#{app.name}-redis-shared-aaa", service_type: "redis", server: server,
        status: :error, tier_name: DatabaseProvisioner::SHARED_TIER, shared: true,
        parent_service: parent, creator: user
      )
      app.app_databases.create!(database_service: db, alias_name: "REDIS")

      svc = described_class.new(app: app, engine: "redis")
      expect(svc.send(:already_attached?)).to eq(false)
    end
  end
end

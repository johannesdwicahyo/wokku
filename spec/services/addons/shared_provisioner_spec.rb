require "rails_helper"

RSpec.describe Addons::SharedProvisioner do
  let(:user)   { create(:user) }
  let(:server) { create(:server) }
  let(:app)    { create(:app_record, creator: user, server: server) }

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
      {
        "redis"       => { service_class: Dokku::SharedRedis,       alias_env: "REDIS",       envs: { "REDIS_URL" => "redis://x:y@h:6379/0" } },
        "memcached"   => { service_class: Dokku::SharedMemcached,   alias_env: "MEMCACHED",   envs: { "MEMCACHED_URL" => "h:11211", "MEMCACHED_KEY_PREFIX" => "myapp:" } },
        "rabbitmq"    => { service_class: Dokku::SharedRabbitmq,    alias_env: "RABBITMQ",    envs: { "RABBITMQ_URL" => "amqp://x:y@h:5672/myapp" } },
        "meilisearch" => { service_class: Dokku::SharedMeilisearch, alias_env: "MEILISEARCH", envs: { "MEILISEARCH_URL" => "http://h:7700", "MEILISEARCH_API_KEY" => "k" } }
      }.each do |engine, cfg|
        context "for #{engine}" do
          let(:wrapper) { instance_double(cfg[:service_class]) }
          let(:dokku_config) { instance_double(Dokku::Config) }
          let(:client) { instance_double(Dokku::Client) }

          before do
            allow(Dokku::Client).to receive(:new).with(server).and_return(client)
            allow(cfg[:service_class]).to receive(:new).with(client).and_return(wrapper)
            allow(wrapper).to receive(:provision_tenant!).with(slug: app.name).and_return(envs: cfg[:envs])
            allow(Dokku::Config).to receive(:new).with(client).and_return(dokku_config)
            allow(dokku_config).to receive(:set)
          end

          it "creates a shared DatabaseService row + sets envs + creates app_database alias" do
            result = described_class.new(app: app, engine: engine).call

            expect(result).to eq(:provisioned)
            db = app.database_services.where(service_type: engine, shared: true).first
            expect(db).to be_present
            expect(db.tier_name).to eq(DatabaseProvisioner::SHARED_TIER)
            expect(db.parent_service.name).to eq("dokku-shared-#{engine}")
            expect(app.app_databases.find_by(database_service: db).alias_name).to eq(cfg[:alias_env])
            expect(dokku_config).to have_received(:set).with(app.name, cfg[:envs])
          end

          it "returns :already_attached on re-run (idempotent)" do
            described_class.new(app: app, engine: engine).call
            expect(described_class.new(app: app, engine: engine).call).to eq(:already_attached)
          end
        end
      end
    end
  end
end

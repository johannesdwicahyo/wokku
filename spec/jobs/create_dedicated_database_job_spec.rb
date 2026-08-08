# frozen_string_literal: true

require "rails_helper"

RSpec.describe CreateDedicatedDatabaseJob, type: :job do
  let(:server) { create(:server) }
  let(:user)   { create(:user) }
  let(:app)    { create(:app_record, creator: user, server: server) }

  # mongodb is the example engine here — the job's happy-path/rollback
  # logic is engine-agnostic (mysql was the original example before
  # dedicated mysql creation was retired; see database_service.rb
  # RETIRED_TYPES).
  let(:dedicated) do
    create(
      :database_service, server: server, service_type: "mongodb",
      name: "#{app.name}-mongo-dedicated", tier_name: "basic",
      shared: false, status: :upgrading_provisioning, creator: user
    )
  end

  before do
    allow(Apps::Restarter).to receive(:restart)
  end

  # Link the AppDatabase row the way the box-creation controller does
  # before enqueueing.
  def link_app!
    AppDatabase.create!(app_record: app, database_service: dedicated, alias_name: "DATABASE")
  end

  def stub_create_op!
    op = build_stubbed(:service_op, status: :succeeded)
    allow(Services::Ops).to receive(:issue_and_wait!)
      .with(service: dedicated, kind: "service.create",
            params: hash_including(:service_type, :image, :admin_pass, :memory_mb, :max_connections, :network, :volume_path))
      .and_return(op)
  end

  describe "happy path" do
    before do
      link_app!
      stub_create_op!
    end

    it "provisions via a service.create op, cuts over, marks running, and sets DATABASE_URL" do
      described_class.new.perform(dedicated.id)

      expect(dedicated.reload.status).to eq("running")
      expect(dedicated.wokkud_managed).to be(true)
      expect(dedicated.dsn).to be_present
      # cp env truth (B6): the DSN lands as an EnvVar row; the dokku
      # mirror died with the flip. The DSN host resolves via the
      # wokku-services overlay every app task runs on — no dokku network
      # attach step remains.
      expect(app.env_vars.find_by(key: "DATABASE_URL")&.value).to eq(dedicated.dsn)
      expect(Apps::Restarter).to have_received(:restart).with(app)
    end

    it "logs an Activity for the created dedicated DB" do
      expect { described_class.new.perform(dedicated.id) }
        .to change(Activity, :count).by(1)

      activity = Activity.last
      expect(activity.action).to eq("addons.dedicated_db.created")
      expect(activity.metadata["engine"]).to eq("mongodb")
    end

    it "supports the mysql and mariadb engine configs" do
      expect(described_class::ENGINE_CONFIG.fetch("mysql"))
        .to eq(alias_name: "DATABASE", env: "DATABASE_URL")
      expect(described_class::ENGINE_CONFIG.fetch("mariadb"))
        .to eq(alias_name: "DATABASE", env: "DATABASE_URL")
    end
  end

  describe "guard: unsupported engine" do
    it "raises KeyError for an engine not in ENGINE_CONFIG" do
      pg = create(
        :database_service, server: server, service_type: "postgres",
        name: "#{app.name}-pg-dedicated", status: :upgrading_provisioning, creator: user
      )
      AppDatabase.create!(app_record: app, database_service: pg, alias_name: "DATABASE")

      expect { described_class.new.perform(pg.id) }.to raise_error(KeyError)
    end
  end

  describe "guard: no app linked" do
    it "raises ProvisioningFailed when no AppDatabase links the dedicated row" do
      expect { described_class.new.perform(dedicated.id) }
        .to raise_error(UpgradeError::ProvisioningFailed, /no app linked/)
    end
  end

  describe "rollback paths" do
    before do
      link_app!
      allow(Sentry).to receive(:capture_exception)
      allow(Services::Ops).to receive(:issue_and_wait!)
        .with(service: dedicated, kind: "service.create", params: anything)
        .and_raise(Services::Ops::Failed.new(build_stubbed(:service_op, status: :failed, error: "create boom")))
    end

    context "when provisioning fails" do
      before do
        allow(Services::Ops).to receive(:issue_and_wait!)
          .with(service: dedicated, kind: "service.destroy", params: { force: true })
          .and_return(build_stubbed(:service_op, status: :succeeded))
      end

      it "tears down via a service.destroy op, destroys the row, reports to Sentry, and re-raises" do
        expect { described_class.new.perform(dedicated.id) }
          .to raise_error(Services::Ops::Failed)

        expect(Services::Ops).to have_received(:issue_and_wait!)
          .with(service: dedicated, kind: "service.destroy", params: { force: true })
        expect(DatabaseService.exists?(dedicated.id)).to be(false)
        expect(Sentry).to have_received(:capture_exception)
      end
    end

    context "when the teardown op during rollback also fails" do
      before do
        allow(Services::Ops).to receive(:issue_and_wait!)
          .with(service: dedicated, kind: "service.destroy", params: { force: true })
          .and_raise(Services::Ops::Timeout, "destroy boom")
      end

      it "still destroys the row and re-raises the original error" do
        expect { described_class.new.perform(dedicated.id) }
          .to raise_error(Services::Ops::Failed)
        expect(DatabaseService.exists?(dedicated.id)).to be(false)
      end
    end
  end
end

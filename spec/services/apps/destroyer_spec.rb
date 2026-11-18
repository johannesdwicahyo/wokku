# frozen_string_literal: true

require "rails_helper"

RSpec.describe Apps::Destroyer do
  let(:server) { create(:server) }
  let(:app_record) { create(:app_record, server: server) }

  before do
    allow(Wokku.config.dns_provider).to receive(:delete_app_record)
    allow(Git::BareRepo).to receive(:new).and_return(instance_double(Git::BareRepo, remove!: true))
  end

  describe ".call" do
    it "destroys an exclusively-linked database via DatabaseProvisioner and leaves a shared-linked one alone" do
      other_app = create(:app_record, server: server)
      exclusive_db = create(:database_service, server: server)
      create(:app_database, app_record: app_record, database_service: exclusive_db, alias_name: "POSTGRES")
      shared_db = create(:database_service, server: server, name: "shared-db")
      create(:app_database, app_record: app_record, database_service: shared_db, alias_name: "POSTGRES")
      create(:app_database, app_record: other_app, database_service: shared_db, alias_name: "POSTGRES")

      allow(DatabaseProvisioner).to receive(:destroy!)

      result = described_class.call(app_record)

      expect(DatabaseProvisioner).to have_received(:destroy!).with(database_service: exclusive_db)
      expect(DatabaseProvisioner).not_to have_received(:destroy!).with(database_service: shared_db)
      expect(result.destroyed_db_names).to eq([ exclusive_db.name ])
      expect(DatabaseService.where(id: shared_db.id)).to exist
    end

    it "removes the Swarm stack, then every image of the app, before app.destroy (order pin)" do
      calls = []
      app_record.update!(wokkud_lifecycle: true)
      allow(Lifecycle::Ops).to receive(:remove!) { |app, **| calls << [ :remove!, app.id ] }
      allow(Lifecycle::Ops).to receive(:issue!) { |app, kind, params, **| calls << [ kind, params ] }
      original_destroy = app_record.method(:destroy!)
      allow(app_record).to receive(:destroy!) do
        calls << [ :destroy!, app_record.id ]
        original_destroy.call
      end

      described_class.call(app_record)

      # An empty keep-list deletes every tag from the host registry and the
      # host's local image copies (they leaked GBs per deleted app before).
      expect(calls).to eq([
        [ :remove!, app_record.id ],
        [ "registry.prune", { "repo" => "wokku/#{app_record.name}", "keep_tags" => [] } ],
        [ :destroy!, app_record.id ]
      ])
    end

    it "still destroys the app when the image prune fails, and collects a warning" do
      app_record.update!(wokkud_lifecycle: true)
      allow(Lifecycle::Ops).to receive(:remove!)
      allow(Lifecycle::Ops).to receive(:issue!).and_raise(Lifecycle::Ops::Timeout, "slow")

      result = described_class.call(app_record)

      expect(AppRecord.where(id: app_record.id)).not_to exist
      expect(result.warnings.join).to include("remove images")
    end

    it "refuses while a deploy is in flight and keeps the app (no orphaned services)" do
      create(:deploy, app_record: app_record, status: :building)
      expect { described_class.call(app_record) }.to raise_error(Lifecycle::Ops::Busy)
      expect(AppRecord.where(id: app_record.id)).to exist
    end

    it "does not let a wedged hours-old deploy block deletion" do
      create(:deploy, app_record: app_record, status: :building, created_at: 3.hours.ago)
      expect { described_class.call(app_record) }.to change(AppRecord, :count).by(-1)
    end

    it "keeps the app when stack.remove collides with a live op" do
      app_record.update!(wokkud_lifecycle: true)
      allow(Lifecycle::Ops).to receive(:remove!).and_raise(Lifecycle::Ops::Busy.new(app_record))
      expect { described_class.call(app_record) }.to raise_error(Lifecycle::Ops::Busy)
      expect(AppRecord.where(id: app_record.id)).to exist
    end

    it "still destroys the app when Cloudflare DNS cleanup raises, and collects a warning" do
      allow(Wokku.config.dns_provider).to receive(:delete_app_record).and_raise(Wokku::Providers::DnsError, "boom")

      result = described_class.call(app_record)

      expect(AppRecord.where(id: app_record.id)).not_to exist
      expect(result.warnings.join).to match(/boom/)
    end

    it "processes every DB even when one raises, collects a warning, and the app row is already gone" do
      db_ok = create(:database_service, server: server)
      db_bad = create(:database_service, server: server, name: "bad-db")
      create(:app_database, app_record: app_record, database_service: db_ok, alias_name: "POSTGRES")
      create(:app_database, app_record: app_record, database_service: db_bad, alias_name: "REDIS")

      allow(DatabaseProvisioner).to receive(:destroy!) do |database_service:|
        raise "kaboom" if database_service == db_bad
      end

      result = described_class.call(app_record)

      expect(AppRecord.where(id: app_record.id)).not_to exist
      expect(DatabaseProvisioner).to have_received(:destroy!).with(database_service: db_ok)
      expect(DatabaseProvisioner).to have_received(:destroy!).with(database_service: db_bad)
      expect(result.destroyed_db_names).to eq([ db_ok.name ])
      expect(result.warnings.join).to match(/kaboom/)
    end

    it "still destroys the app when the bare repo removal raises, and collects a warning" do
      allow(Git::BareRepo).to receive(:new).and_return(instance_double(Git::BareRepo).tap { |r|
        allow(r).to receive(:remove!).and_raise("no repo")
      })

      result = described_class.call(app_record)

      expect(AppRecord.where(id: app_record.id)).not_to exist
      expect(result.warnings.join).to match(/no repo/)
    end

    it "returns a Result carrying destroyed_db_names and warnings" do
      result = described_class.call(app_record)

      expect(result.destroyed_db_names).to eq([])
      expect(result.warnings).to eq([])
    end

    it "propagates when app.destroy! fails instead of swallowing it" do
      allow(app_record).to receive(:destroy!).and_raise(ActiveRecord::RecordNotDestroyed.new("nope", app_record))

      expect { described_class.call(app_record) }.to raise_error(ActiveRecord::RecordNotDestroyed)
    end
  end

  it "never references Dokku:: anywhere in the destroyer" do
    source = File.read(Wokku::Engine.root.join("app/services/apps/destroyer.rb"))
    expect(source).not_to match(/Dokku::/)
  end
end

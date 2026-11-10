# frozen_string_literal: true

require "rails_helper"

# Coverage variant for BackupService guard paths — the managed export op
# happy/failure paths live in backup_service_spec.rb. Every backup is a
# wokkud service.export op (legacy SSH export leg deleted in W7 Phase 1).
RSpec.describe BackupService do
  let(:team) { create(:team) }
  let(:server) { create(:server, team: team) }
  let(:db) { create(:database_service, server: server, service_type: "postgres", name: "pg-main") }

  let!(:destination) do
    server.create_backup_destination!(
      enabled: true,
      provider: "r2",
      bucket: "wokku-backups",
      path_prefix: "dbs/pg-main",
      access_key_id: "AKID",
      secret_access_key: "SECRET",
      region: "auto"
    )
  end

  describe "#perform!" do
    it "raises and creates nothing when server has no backup destination" do
      allow(db).to receive(:server).and_return(server)
      allow(server).to receive(:backup_destination).and_return(nil)

      service = described_class.new(db)
      expect { service.perform! }.to raise_error(/No backup destination configured/)
      expect(db.backups.count).to eq(0)
    end

    it "refuses memcached up front and creates no backup row" do
      db.update_column(:service_type, "memcached")
      expect(Services::Ops).not_to receive(:issue_and_wait!)

      expect { described_class.new(db).perform! }.to raise_error(ArgumentError, /Memcached/)
      expect(db.backups.count).to eq(0)
    end
  end

  describe "shared mariadb tenant export" do
    let(:parent) do
      create(:database_service, server: server, service_type: "mariadb", name: "dokku-shared-mariadb",
                                tier_name: "shared_host", wokkud_managed: true)
    end
    let(:tenant) do
      create(:database_service, server: server, service_type: "mariadb", name: "shop-mariadb-shared-abc123",
                                shared: true, tier_name: "shared_free", parent_service: parent,
                                shared_db_name: "shop", wokkud_managed: true,
                                dsn: "mysql://shop:tenantpw@dokku-shared-mariadb:3306/shop")
    end

    it "dumps the tenant db through the PARENT, WKB1-keyed, without the tenant's password" do
      allow(EnvelopeCipher).to receive(:public_key_pem).and_return("PEM")
      allow(server.backup_destination).to receive(:s3_presigned_put).and_return("https://put")
      allow(tenant).to receive(:server).and_return(server)
      expect(Services::Ops).to receive(:issue_and_wait!)
        .with(service: parent, kind: "service.export",
              params: { service_type: "mariadb", database: "shop", presigned_put_url: "https://put", public_key_pem: "PEM" })
        .and_return(build_stubbed(:service_op, status: :succeeded, result: { "bytes" => 42 }))

      backup = described_class.new(tenant).perform!

      expect(backup).to have_attributes(status: "completed", encrypted: true, size_bytes: 42)
      expect(backup.s3_key).to include("/mariadb/shop-mariadb-shared-abc123/")
    end

    it "farewell-snapshots a shared mariadb tenant (shared_free policy) — mariadb is backupable" do
      expect(tenant.backup_policy[:on_destroy_snapshot]).to be(true)
      expect(BackupSchedulerJob::BACKUPABLE_TYPES).to include("mariadb")
    end
  end

  describe "#export_command" do
    it "maps each supported type" do
      {
        "postgres" => "postgres:export",
        "mysql" => "mysql:export",
        "mariadb" => "mariadb:export",
        "mongodb" => "mongo:export",
        "redis" => "redis:export"
      }.each do |type, cmd|
        svc = described_class.new(DatabaseService.new(name: "d", service_type: type))
        expect(svc.send(:export_command)).to eq("#{cmd} d")
      end
    end

    it "raises for an unmapped type" do
      svc = described_class.new(DatabaseService.new(name: "d", service_type: "memcached"))
      expect { svc.send(:export_command) }.to raise_error(/Unsupported database type for backup/)
    end
  end
end

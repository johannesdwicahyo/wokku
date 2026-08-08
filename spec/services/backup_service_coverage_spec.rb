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

    it "raises for an unsupported database type and marks the backup failed" do
      db.update_column(:service_type, "memcached")
      allow(db).to receive(:server).and_return(server)
      allow(server).to receive(:backup_destination).and_return(destination)
      expect(Services::Ops).not_to receive(:issue_and_wait!)

      service = described_class.new(db)
      # The export_command guard raises inside perform_managed!, so the
      # running backup row is created first then flipped to failed.
      expect { service.perform! }.to raise_error(/Unsupported database type for backup/)
      expect(db.backups.last.status).to eq("failed")
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

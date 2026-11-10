# frozen_string_literal: true

require "rails_helper"

RSpec.describe BackupService do
  def with_env(vars)
    saved = ENV.to_h
    vars.each { |k, v| ENV[k] = v }
    yield
  ensure
    ENV.replace(saved)
  end

  around { |ex| with_env("BACKUP_ENCRYPTION_KEY" => Base64.strict_encode64("k" * 32)) { ex.run } }

  describe "#export_command" do
    it "returns correct command for postgres" do
      db = DatabaseService.new(name: "my-db", service_type: "postgres")
      service = described_class.new(db)
      expect(service.send(:export_command)).to eq("postgres:export my-db")
    end

    it "returns correct command for mysql" do
      db = DatabaseService.new(name: "my-db", service_type: "mysql")
      service = described_class.new(db)
      expect(service.send(:export_command)).to eq("mysql:export my-db")
    end

    it "returns correct command for redis" do
      db = DatabaseService.new(name: "my-cache", service_type: "redis")
      service = described_class.new(db)
      expect(service.send(:export_command)).to eq("redis:export my-cache")
    end

    it "raises for memcached (no export path)" do
      db = DatabaseService.new(name: "my-mc", service_type: "memcached")
      expect { described_class.new(db).send(:export_command) }
        .to raise_error(/Unsupported database type/)
    end
  end

  describe "#generate_s3_key" do
    it "generates timestamped path" do
      db = DatabaseService.new(name: "my-db", service_type: "postgres")
      service = described_class.new(db)
      key = service.send(:generate_s3_key, "wokku-backups")
      expect(key).to match(%r{wokku-backups/postgres/my-db/\d{4}-\d{2}-\d{2}})
    end
  end

  describe "#perform! wokkud branching (Phase B4)" do
    let(:server) { create(:server) }

    let!(:destination) do
      server.create_backup_destination!(
        enabled: true, provider: "r2", bucket: "wokku-backups",
        path_prefix: "dbs/pg-main", access_key_id: "AKID",
        secret_access_key: "SECRET", region: "auto"
      )
    end

    context "with a wokkud-managed dedicated database" do
      let(:db) do
        create(:database_service, server: server, service_type: "postgres", name: "pg-main",
               wokkud_managed: true, dsn: "postgres://postgres:s3cr3t@dokku.postgres.pg-main:5432/pg-main")
      end

      before do
        allow(EnvelopeCipher).to receive(:public_key_pem)
          .and_return("-----BEGIN PUBLIC KEY-----\nFAKE\n-----END PUBLIC KEY-----\n")
      end

      it "sends the envelope public key and records an encrypted .gz.enc backup" do
        op = build_stubbed(:service_op, status: :succeeded, result: { "bytes" => 4096 })
        expect(Services::Ops).to receive(:issue_and_wait!)
          .with(service: db, kind: "service.export",
                params: hash_including(public_key_pem: a_string_starting_with("-----BEGIN PUBLIC KEY-----")))
          .and_return(op)

        backup = described_class.new(db).perform!

        expect(backup.encrypted).to be(true)
        expect(backup.s3_key).to end_with(".gz.enc")
      end

      it "issues a service.export op with a presigned PUT URL and never SSHes" do
        op = build_stubbed(:service_op, status: :succeeded, result: { "bytes" => 4096 })
        expect(Services::Ops).to receive(:issue_and_wait!)
          .with(service: db, kind: "service.export",
                # The db INSIDE the container is underscored (dokku plugin
                # convention, every provisioning path mirrors it) — exporting
                # the hyphenated row name fails "database does not exist"
                # (batumas-postgres, first W1 adoption backup proof).
                params: hash_including(service_type: "postgres", database: "pg_main", presigned_put_url: kind_of(String)))
          .and_return(op)
        expect(Hosts::Ssh).not_to receive(:new)

        backup = described_class.new(db).perform!

        expect(backup.status).to eq("completed")
        expect(backup.size_bytes).to eq(4096)
        expect(backup.completed_at).to be_present
      end

      it "marks the backup failed and re-raises when the op fails" do
        allow(Services::Ops).to receive(:issue_and_wait!).and_raise(Services::Ops::Failed.new(build_stubbed(:service_op, status: :failed, error: "boom")))

        expect { described_class.new(db).perform! }.to raise_error(Services::Ops::Failed)

        expect(db.backups.last.status).to eq("failed")
      end

      it "fails closed instead of silently producing a plaintext backup marked encrypted when the envelope key is missing" do
        allow(EnvelopeCipher).to receive(:public_key_pem).and_raise(EnvelopeCipher::Error, "backup_envelope.private_key not set in Rails credentials")
        expect(Services::Ops).not_to receive(:issue_and_wait!)

        expect { described_class.new(db).perform! }.to raise_error(EnvelopeCipher::Error)

        backup = db.backups.last
        expect(backup.status).to eq("failed")
        expect(backup.error_message).to be_present
      end
    end
  end
end

# frozen_string_literal: true

require "rails_helper"
require "aws-sdk-s3"

RSpec.describe BackupReencryptSweep do
  def with_env(vars)
    saved = ENV.to_h
    vars.each { |k, v| ENV[k] = v }
    yield
  ensure
    ENV.replace(saved)
  end

  let(:test_key) { OpenSSL::PKey::RSA.new(File.read(Rails.root.join("spec/fixtures/envelope/test_key.pem"))) }
  let(:server) { create(:server) }
  let(:destination) { create(:backup_destination, server: server) }
  let(:db) { create(:database_service, server: server, service_type: "postgres", wokkud_managed: true) }
  let(:s3) { instance_double(Aws::S3::Client) }

  before do
    allow(EnvelopeCipher).to receive(:public_key_pem).and_return(test_key.public_key.to_pem)
    allow(EnvelopeCipher).to receive(:master_private_key).and_return(test_key)
    allow_any_instance_of(BackupDestination).to receive(:s3_client).and_return(s3)
  end

  # Serves `content` for every download the sweep performs.
  def serve(content)
    allow(s3).to receive(:get_object) do |bucket:, key:, response_target:|
      File.binwrite(response_target, content)
    end
  end

  it "envelope-encrypts a plaintext managed backup under a .enc key and deletes the old object, only after the record is updated" do
    backup = create(:backup, database_service: db, backup_destination: destination,
                    status: "completed", encrypted: false, s3_key: "dbs/pg/1.gz")
    serve("plaintext-gzip-bytes")
    uploaded = {}
    calls = []
    allow(s3).to receive(:put_object) { |bucket:, key:, body:, content_type:| uploaded[key] = body.read; calls << :put }
    allow(s3).to receive(:delete_object) do |bucket:, key:|
      # Captured from inside the stub so it proves the DB row was already
      # flipped to the new key by the time delete_object fires — not just
      # that delete_object was called at some point.
      calls << [ :delete, key, Backup.find(backup.id).s3_key ]
    end

    result = described_class.call

    expect(result[:swept]).to eq(1)
    expect(backup.reload.s3_key).to eq("dbs/pg/1.gz.enc")
    expect(backup.encrypted).to be(true)
    expect(uploaded.keys).to eq([ "dbs/pg/1.gz.enc" ])
    expect(uploaded["dbs/pg/1.gz.enc"].byteslice(0, 4)).to eq("WKB1")
    expect(calls).to eq([ :put, [ :delete, "dbs/pg/1.gz", "dbs/pg/1.gz.enc" ] ])
  end

  it "counts the record as swept (and logs an ORPHANED warning) when delete_object fails after the record is already updated" do
    backup = create(:backup, database_service: db, backup_destination: destination,
                    status: "completed", encrypted: false, s3_key: "dbs/pg/orphan.gz")
    serve("plaintext-gzip-bytes")
    allow(s3).to receive(:put_object)
    allow(s3).to receive(:delete_object).and_raise(Aws::S3::Errors::ServiceError.new(nil, "network blip"))
    allow(Rails.logger).to receive(:error)

    result = described_class.call

    expect(result[:swept]).to eq(1)
    expect(result[:failed]).to eq(0)
    expect(backup.reload.s3_key).to eq("dbs/pg/orphan.gz.enc")
    expect(backup.encrypted).to be(true)
    expect(Rails.logger).to have_received(:error).with(/ORPHANED.*dbs\/pg\/orphan\.gz/)
  end

  it "converts a legacy fleet-key blob in place (same key, no delete)" do
    backup = create(:backup, database_service: db, backup_destination: destination,
                    status: "completed", encrypted: true, s3_key: "dbs/pg/2.gz.enc")
    plain = Tempfile.create("p"); plain.write("legacy-payload"); plain.close
    with_env("BACKUP_ENCRYPTION_KEY" => Base64.strict_encode64(SecureRandom.random_bytes(32))) do
      legacy_blob = File.binread(BackupCipher.encrypt_file(plain.path))
      serve(legacy_blob)
      allow(s3).to receive(:put_object)
      expect(s3).not_to receive(:delete_object)

      result = described_class.call

      expect(result[:swept]).to eq(1)
      expect(backup.reload.s3_key).to eq("dbs/pg/2.gz.enc")
    end
  end

  it "skips objects that are already envelopes (idempotent re-run)" do
    create(:backup, database_service: db, backup_destination: destination,
           status: "completed", encrypted: true, s3_key: "dbs/pg/3.gz.enc")
    plain = Tempfile.create("p"); plain.write("x"); plain.close
    serve(File.binread(EnvelopeCipher.encrypt_file(plain.path, public_key: test_key.public_key)))
    expect(s3).not_to receive(:put_object)

    expect(described_class.call[:skipped]).to eq(1)
  end

  it "skips non-managed and volume backups entirely" do
    legacy_db = create(:database_service, server: server, wokkud_managed: false)
    create(:backup, database_service: legacy_db, backup_destination: destination, status: "completed")
    create(:backup, :volume, backup_destination: destination, status: "completed", app_record: create(:app_record))
    expect(s3).not_to receive(:get_object)

    result = described_class.call

    expect(result).to eq(swept: 0, skipped: 0, failed: 0)
  end

  it "sweeps a detached farewell snapshot (database_service nil, not volume kind)" do
    # Presence validation on database_service is scoped to on: :create (see
    # commit a9cea1bc) — a farewell snapshot detaches AFTER creation, once
    # its owning DatabaseService is destroyed, so mirror that here instead
    # of trying to build a database-kind row with a nil association.
    backup = create(:backup, database_service: db, backup_destination: destination,
                    status: "completed", encrypted: false, s3_key: "dbs/pg/farewell.gz")
    backup.update!(database_service_id: nil)
    serve("plaintext-gzip-bytes")
    allow(s3).to receive(:put_object)
    allow(s3).to receive(:delete_object)

    result = described_class.call

    expect(result[:swept]).to eq(1)
    expect(backup.reload.s3_key).to eq("dbs/pg/farewell.gz.enc")
    expect(backup.encrypted).to be(true)
  end

  it "logs and continues past a per-backup failure, leaving the record untouched" do
    backup = create(:backup, database_service: db, backup_destination: destination,
                    status: "completed", encrypted: false, s3_key: "dbs/pg/4.gz")
    allow(s3).to receive(:get_object).and_raise(Aws::S3::Errors::NoSuchKey.new(nil, "gone"))

    result = described_class.call

    expect(result[:failed]).to eq(1)
    expect(backup.reload.encrypted).to be(false)
  end
end

# frozen_string_literal: true

require "rails_helper"
require "aws-sdk-s3"

RSpec.describe RestoreService do
  def with_env(vars)
    saved = ENV.to_h
    vars.each { |k, v| ENV[k] = v }
    yield
  ensure
    ENV.replace(saved)
  end

  def build_restore_service(db_type: "postgres", ssh_user: "dokku", ssh_key: nil, encrypted: false)
    server = Server.new(
      host: "10.0.0.1",
      port: 22,
      ssh_user: ssh_user,
      ssh_private_key: ssh_key
    )
    db = DatabaseService.new(name: "pg-main", service_type: db_type, server: server)
    destination = BackupDestination.new(
      bucket: "wokku-backups",
      region: "us-east-1",
      access_key_id: "AKID",
      secret_access_key: "SECRET"
    )
    backup = Backup.new(
      database_service: db,
      backup_destination: destination,
      s3_key: "wokku-backups/postgres/pg-main/2026-04-01/backup.sql.gz",
      encrypted: encrypted
    )
    described_class.new(backup)
  end

  def write_empty_gzip(path)
    require "zlib"
    Zlib::GzipWriter.open(path) { |gz| gz.write("") }
  end

  def stub_tempfile_with_gzip
    tmp = Tempfile.new([ "restore_test", ".gz" ], binmode: true)
    write_empty_gzip(tmp.path)
    original = Tempfile.method(:new)
    Tempfile.define_singleton_method(:new) { |*_args, **_kwargs| tmp }
    yield tmp
  ensure
    Tempfile.define_singleton_method(:new, original)
    tmp&.close
    tmp&.unlink rescue nil
  end

  def stub_s3_on(service, &writer)
    require "zlib"
    writer ||= ->(target) { Zlib::GzipWriter.open(target) { |gz| gz.write("") } }
    mock_s3 = Object.new
    mock_s3.define_singleton_method(:get_object) do |opts|
      writer.call(opts[:response_target])
    end
    service.instance_variable_get(:@destination)
           .define_singleton_method(:s3_client) { mock_s3 }
  end

  def build_mock_ssh_channel(executed_commands, fed = nil)
    mock_channel = Object.new
    mock_channel.define_singleton_method(:exec) { |cmd, &block|
      executed_commands << cmd
      block.call(mock_channel, true)
    }
    mock_channel.define_singleton_method(:send_data) { |data| fed << data if fed }
    mock_channel.define_singleton_method(:eof!) { }
    mock_channel.define_singleton_method(:on_extended_data) { |&_b| }
    mock_channel.define_singleton_method(:wait) { }
    mock_channel
  end

  def with_stubbed_ssh(mock_channel, &block)
    original = Net::SSH.method(:start)
    Net::SSH.define_singleton_method(:start) do |_host, _user, _opts, &blk|
      mock_ssh = Object.new
      mock_ssh.define_singleton_method(:open_channel) { |&b|
        b.call(mock_channel)
        mock_channel
      }
      blk.call(mock_ssh)
    end
    yield
  ensure
    Net::SSH.define_singleton_method(:start, original)
  end

  it "IMPORT_COMMANDS maps all supported database types" do
    expect(described_class::IMPORT_COMMANDS["postgres"]).to eq("postgres:import")
    expect(described_class::IMPORT_COMMANDS["mysql"]).to eq("mysql:import")
    expect(described_class::IMPORT_COMMANDS["mariadb"]).to eq("mariadb:import")
    expect(described_class::IMPORT_COMMANDS["mongodb"]).to eq("mongo:import")
    expect(described_class::IMPORT_COMMANDS["redis"]).to eq("redis:import")
  end

  it "perform! raises for unsupported db type" do
    service = build_restore_service(db_type: "cassandra")
    expect { service.perform! }.to raise_error(RuntimeError, /Unsupported database type/)
  end

  it "perform! downloads from S3 and runs ssh import for postgres" do
    service = build_restore_service(db_type: "postgres", ssh_user: "dokku")
    executed_commands = []

    stub_tempfile_with_gzip do
      stub_s3_on(service)
      mock_channel = build_mock_ssh_channel(executed_commands)
      with_stubbed_ssh(mock_channel) do
        result = service.perform!
        expect(result).to eq(true)
      end
    end

    expect(executed_commands.length).to eq(1)
    expect(executed_commands.first).to eq("postgres:import pg-main")
  end

  it "perform! uses correct import command for mysql" do
    service = build_restore_service(db_type: "mysql", ssh_user: "dokku")
    executed_commands = []

    stub_tempfile_with_gzip do
      stub_s3_on(service)
      mock_channel = build_mock_ssh_channel(executed_commands)
      with_stubbed_ssh(mock_channel) do
        service.perform!
      end
    end

    expect(executed_commands.first).to eq("mysql:import pg-main")
  end

  it "perform! prepends 'dokku' to command when ssh_user is not dokku" do
    service = build_restore_service(db_type: "postgres", ssh_user: "ubuntu")
    executed_commands = []

    stub_tempfile_with_gzip do
      stub_s3_on(service)
      mock_channel = build_mock_ssh_channel(executed_commands)
      with_stubbed_ssh(mock_channel) do
        service.perform!
      end
    end

    expect(executed_commands.first).to eq("dokku postgres:import pg-main")
  end

  it "perform! re-raises on SSH failure" do
    service = build_restore_service(db_type: "mysql")

    stub_tempfile_with_gzip do
      stub_s3_on(service)
      original = Net::SSH.method(:start)
      Net::SSH.define_singleton_method(:start) { |*_args, **_opts, &_b|
        raise Net::SSH::AuthenticationFailed.new("test")
      }
      begin
        expect { service.perform! }.to raise_error(Net::SSH::AuthenticationFailed)
      ensure
        Net::SSH.define_singleton_method(:start, original)
      end
    end
  end

  it "perform! passes ssh key_data when server has private key" do
    private_key = "-----BEGIN RSA PRIVATE KEY-----\ntest-key-data\n-----END RSA PRIVATE KEY-----"
    service = build_restore_service(db_type: "postgres", ssh_user: "dokku", ssh_key: private_key)
    captured_opts = nil

    stub_tempfile_with_gzip do
      stub_s3_on(service)
      mock_channel = build_mock_ssh_channel([])
      original = Net::SSH.method(:start)
      Net::SSH.define_singleton_method(:start) do |_host, _user, opts, &blk|
        captured_opts = opts
        mock_ssh = Object.new
        mock_ssh.define_singleton_method(:open_channel) { |&b|
          b.call(mock_channel)
          mock_channel
        }
        blk.call(mock_ssh)
      end
      begin
        service.perform!
      ensure
        Net::SSH.define_singleton_method(:start, original)
      end
    end

    expect(captured_opts.key?(:key_data)).to be_truthy
    expect(captured_opts[:key_data].first).to include("BEGIN RSA PRIVATE KEY")
  end

  it "perform! connects with correct SSH options" do
    service = build_restore_service(db_type: "postgres", ssh_user: "dokku")
    captured_host = nil
    captured_user = nil
    captured_opts = nil

    stub_tempfile_with_gzip do
      stub_s3_on(service)
      mock_channel = build_mock_ssh_channel([])
      original = Net::SSH.method(:start)
      Net::SSH.define_singleton_method(:start) do |host, user, opts, &blk|
        captured_host = host
        captured_user = user
        captured_opts = opts
        mock_ssh = Object.new
        mock_ssh.define_singleton_method(:open_channel) { |&b|
          b.call(mock_channel)
          mock_channel
        }
        blk.call(mock_ssh)
      end
      begin
        service.perform!
      ensure
        Net::SSH.define_singleton_method(:start, original)
      end
    end

    expect(captured_host).to eq("10.0.0.1")
    expect(captured_user).to eq("dokku")
    expect(captured_opts[:port]).to eq(22)
    expect(captured_opts[:non_interactive]).to eq(true)
  end

  describe "#perform! wokkud branching (Phase B4)" do
    let(:server)      { Server.new(host: "10.0.0.1", port: 22, ssh_user: "dokku") }
    let(:destination) { BackupDestination.new(bucket: "wokku-backups", region: "us-east-1", access_key_id: "AKID", secret_access_key: "SECRET") }

    context "with a wokkud-managed database" do
      let(:db) do
        DatabaseService.new(name: "pg-main", service_type: "postgres", server: server,
                             wokkud_managed: true, dsn: "postgres://postgres:s3cr3t@dokku.postgres.pg-main:5432/pg-main")
      end
      let(:backup) { Backup.new(database_service: db, backup_destination: destination, s3_key: "dbs/pg-main/backup.gz") }

      it "issues a service.import op with a presigned GET URL and never SSHes" do
        allow(destination).to receive(:s3_presigned_url).with(backup.s3_key).and_return("https://r2.example/get")
        op = build_stubbed(:service_op, status: :succeeded)
        expect(Services::Ops).to receive(:issue_and_wait!)
          .with(service: db, kind: "service.import",
                params: hash_including(service_type: "postgres", database: "pg_main", presigned_get_url: "https://r2.example/get"))
          .and_return(op)
        expect(Net::SSH).not_to receive(:start)

        result = described_class.new(backup).perform!

        expect(result).to eq(true)
      end

      context "with an encrypted (WKB1) backup" do
        let(:test_key) { OpenSSL::PKey::RSA.new(File.read(Rails.root.join("spec/fixtures/envelope/test_key.pem"))) }
        let(:backup) do
          Backup.new(database_service: db, backup_destination: destination,
                     s3_key: "dbs/pg-main/backup.gz.enc", encrypted: true)
        end
        let(:header) do
          plain = Tempfile.create("p"); plain.write("x"); plain.close
          enc = EnvelopeCipher.encrypt_file(plain.path, public_key: test_key.public_key)
          File.binread(enc, 1024)
        ensure
          File.unlink(enc) if enc && File.exist?(enc)
        end

        it "unwraps the DEK from a ranged header GET and sends it in the import params" do
          allow(EnvelopeCipher).to receive(:master_private_key).and_return(test_key)
          allow(destination).to receive(:s3_presigned_url).and_return("https://r2.example/get")
          s3 = instance_double(Aws::S3::Client)
          allow(destination).to receive(:s3_client).and_return(s3)
          expect(s3).to receive(:get_object)
            .with(bucket: destination.bucket, key: backup.s3_key, range: "bytes=0-1023")
            .and_return(double(body: StringIO.new(header)))

          sent = nil
          expect(Services::Ops).to receive(:issue_and_wait!) do |service:, kind:, params:|
            sent = params
            build_stubbed(:service_op, status: :succeeded)
          end

          described_class.new(backup).perform!

          expect(Base64.strict_decode64(sent[:dek]).bytesize).to eq(32)
        end
      end

      it "omits dek for pre-sweep plaintext backups" do
        allow(destination).to receive(:s3_presigned_url).and_return("https://r2.example/get")
        expect(Services::Ops).to receive(:issue_and_wait!) do |service:, kind:, params:|
          expect(params).not_to have_key(:dek)
          build_stubbed(:service_op, status: :succeeded)
        end

        described_class.new(backup).perform!
      end
    end

    context "when the flag is off (regression)" do
      it "still runs the legacy ssh import, never touching Services::Ops" do
        service = build_restore_service(db_type: "postgres", ssh_user: "dokku")
        executed_commands = []

        stub_tempfile_with_gzip do
          stub_s3_on(service)
          mock_channel = build_mock_ssh_channel(executed_commands)
          with_stubbed_ssh(mock_channel) do
            expect(Services::Ops).not_to receive(:issue_and_wait!)
            result = service.perform!
            expect(result).to eq(true)
          end
        end

        expect(executed_commands.first).to eq("postgres:import pg-main")
      end
    end
  end

  describe "#perform! with encrypted backups" do
    def gzip_bytes(payload)
      tmp = Tempfile.new(binmode: true)
      Zlib::GzipWriter.open(tmp.path) { |gz| gz.write(payload) }
      tmp.path
    end

    around do |example|
      with_env("BACKUP_ENCRYPTION_KEY" => Base64.strict_encode64("k" * 32)) { example.run }
    end

    it "decrypts an encrypted backup before gunzip+import and unlinks the plaintext temp" do
      service = build_restore_service(encrypted: true)
      enc_path = BackupCipher.encrypt_file(gzip_bytes("DUMP"))
      stub_s3_on(service) { |target| FileUtils.cp(enc_path, target) }

      dec_path = nil
      allow(BackupCipher).to receive(:decrypt_file).and_wrap_original do |m, arg|
        dec_path = m.call(arg)
      end

      fed = +""
      mock_channel = build_mock_ssh_channel([], fed)
      with_stubbed_ssh(mock_channel) do
        expect(service.perform!).to eq(true)
      end

      expect(fed).to eq("DUMP")
      expect(File.exist?(dec_path)).to be(false)
    end

    it "restores an unencrypted backup unchanged (back-compat, no decrypt)" do
      service = build_restore_service(encrypted: false)
      stub_s3_on(service) { |target| FileUtils.cp(gzip_bytes("DUMP"), target) }
      expect(BackupCipher).not_to receive(:decrypt_file)

      fed = +""
      mock_channel = build_mock_ssh_channel([], fed)
      with_stubbed_ssh(mock_channel) do
        expect(service.perform!).to eq(true)
      end

      expect(fed).to eq("DUMP")
    end

    it "surfaces BackupCipher::Error on a tampered blob instead of a gzip error" do
      service = build_restore_service(encrypted: true)
      bytes = File.binread(BackupCipher.encrypt_file(gzip_bytes("DUMP"))).dup
      bytes[-1] = (bytes[-1].ord ^ 0x01).chr
      stub_s3_on(service) { |target| File.binwrite(target, bytes) }

      mock_channel = build_mock_ssh_channel([])
      with_stubbed_ssh(mock_channel) do
        expect { service.perform! }.to raise_error(BackupCipher::Error, /integrity/)
      end
    end
  end
end

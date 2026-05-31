# frozen_string_literal: true

require "rails_helper"

RSpec.describe RestoreService do
  def build_restore_service(db_type: "postgres", ssh_user: "dokku", ssh_key: nil)
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
      s3_key: "wokku-backups/postgres/pg-main/2026-04-01/backup.sql.gz"
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

  def stub_s3_on(service)
    require "zlib"
    mock_s3 = Object.new
    mock_s3.define_singleton_method(:get_object) do |opts|
      Zlib::GzipWriter.open(opts[:response_target]) { |gz| gz.write("") }
    end
    service.instance_variable_get(:@destination)
           .define_singleton_method(:s3_client) { mock_s3 }
  end

  def build_mock_ssh_channel(executed_commands)
    mock_channel = Object.new
    mock_channel.define_singleton_method(:exec) { |cmd, &block|
      executed_commands << cmd
      block.call(mock_channel, true)
    }
    mock_channel.define_singleton_method(:send_data) { |_data| }
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
end

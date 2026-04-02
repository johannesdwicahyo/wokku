require "test_helper"

class RestoreServiceTest < ActiveSupport::TestCase
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
    RestoreService.new(backup)
  end

  def write_empty_gzip(path)
    require "zlib"
    Zlib::GzipWriter.open(path) { |gz| gz.write("") }
  end

  def stub_tempfile_with_gzip
    # Create a real Tempfile with valid gzip content for the duration of the block
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
    # The service uses `ch` (the open_channel block param) for send_data, eof!, on_extended_data
    # and `ch.exec` — so all these methods must be on the same channel object
    mock_channel.define_singleton_method(:exec) { |cmd, &block|
      executed_commands << cmd
      # Pass self as _ch so the block's _ch param is also usable; the service uses ch not _ch
      block.call(mock_channel, true)
    }
    mock_channel.define_singleton_method(:send_data) { |_data| }
    mock_channel.define_singleton_method(:eof!) {}
    mock_channel.define_singleton_method(:on_extended_data) { |&_b| }
    mock_channel.define_singleton_method(:wait) {}
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

  test "IMPORT_COMMANDS maps all supported database types" do
    assert_equal "postgres:import", RestoreService::IMPORT_COMMANDS["postgres"]
    assert_equal "mysql:import",    RestoreService::IMPORT_COMMANDS["mysql"]
    assert_equal "mariadb:import",  RestoreService::IMPORT_COMMANDS["mariadb"]
    assert_equal "mongo:import",    RestoreService::IMPORT_COMMANDS["mongodb"]
    assert_equal "redis:import",    RestoreService::IMPORT_COMMANDS["redis"]
  end

  test "perform! raises for unsupported db type" do
    service = build_restore_service(db_type: "cassandra")
    assert_raises(RuntimeError, /Unsupported database type/) do
      service.perform!
    end
  end

  test "perform! downloads from S3 and runs ssh import for postgres" do
    service = build_restore_service(db_type: "postgres", ssh_user: "dokku")
    executed_commands = []

    stub_tempfile_with_gzip do
      stub_s3_on(service)
      mock_channel = build_mock_ssh_channel(executed_commands)
      with_stubbed_ssh(mock_channel) do
        result = service.perform!
        assert_equal true, result
      end
    end

    assert_equal 1, executed_commands.length
    assert_equal "postgres:import pg-main", executed_commands.first
  end

  test "perform! uses correct import command for mysql" do
    service = build_restore_service(db_type: "mysql", ssh_user: "dokku")
    executed_commands = []

    stub_tempfile_with_gzip do
      stub_s3_on(service)
      mock_channel = build_mock_ssh_channel(executed_commands)
      with_stubbed_ssh(mock_channel) do
        service.perform!
      end
    end

    assert_equal "mysql:import pg-main", executed_commands.first
  end

  test "perform! prepends 'dokku' to command when ssh_user is not dokku" do
    service = build_restore_service(db_type: "postgres", ssh_user: "ubuntu")
    executed_commands = []

    stub_tempfile_with_gzip do
      stub_s3_on(service)
      mock_channel = build_mock_ssh_channel(executed_commands)
      with_stubbed_ssh(mock_channel) do
        service.perform!
      end
    end

    assert_equal "dokku postgres:import pg-main", executed_commands.first
  end

  test "perform! re-raises on SSH failure" do
    service = build_restore_service(db_type: "mysql")

    stub_tempfile_with_gzip do
      stub_s3_on(service)
      original = Net::SSH.method(:start)
      Net::SSH.define_singleton_method(:start) { |*_args, **_opts, &_b|
        raise Net::SSH::AuthenticationFailed.new("test")
      }
      begin
        assert_raises(Net::SSH::AuthenticationFailed) { service.perform! }
      ensure
        Net::SSH.define_singleton_method(:start, original)
      end
    end
  end

  test "perform! passes ssh key_data when server has private key" do
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

    assert captured_opts.key?(:key_data)
    assert_includes captured_opts[:key_data].first, "BEGIN RSA PRIVATE KEY"
  end

  test "perform! connects with correct SSH options" do
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

    assert_equal "10.0.0.1", captured_host
    assert_equal "dokku", captured_user
    assert_equal 22, captured_opts[:port]
    assert_equal true, captured_opts[:non_interactive]
  end
end

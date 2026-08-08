# frozen_string_literal: true

require "rails_helper"

RSpec.describe ImportService do
  # Builds an in-memory service. No DB rows needed — the service only reads
  # plain attributes off the database_service / server objects.
  def build_service(db_type: "postgres", ssh_user: "dokku", ssh_key: nil,
                    port: 22, name: "pg-main", dump: "DUMPDATA")
    server = Server.new(
      host: "10.0.0.1",
      port: port,
      ssh_user: ssh_user,
      ssh_private_key: ssh_key
    )
    db = DatabaseService.new(name: name, service_type: db_type, server: server)
    described_class.new(database_service: db, dump_io: StringIO.new(dump))
  end

  def build_mock_ssh_channel(executed_commands, sent_chunks: [], exec_success: true)
    mock_channel = Object.new
    mock_channel.define_singleton_method(:exec) do |cmd, &block|
      executed_commands << cmd
      block.call(mock_channel, exec_success)
    end
    mock_channel.define_singleton_method(:send_data) { |data| sent_chunks << data }
    mock_channel.define_singleton_method(:eof!) { }
    mock_channel.define_singleton_method(:on_extended_data) { |&_b| }
    mock_channel.define_singleton_method(:wait) { }
    mock_channel
  end

  def with_stubbed_ssh(mock_channel)
    original = Net::SSH.method(:start)
    captured = {}
    Net::SSH.define_singleton_method(:start) do |host, user, opts, &blk|
      captured[:host] = host
      captured[:user] = user
      captured[:opts] = opts
      mock_ssh = Object.new
      mock_ssh.define_singleton_method(:open_channel) do |&b|
        b.call(mock_channel)
        mock_channel
      end
      blk.call(mock_ssh)
    end
    yield captured
  ensure
    Net::SSH.define_singleton_method(:start, original)
  end

  describe "IMPORT_COMMANDS" do
    it "maps every supported database type to its dokku import command" do
      expect(described_class::IMPORT_COMMANDS).to eq(
        "postgres" => "postgres:import",
        "mysql"    => "mysql:import",
        "mariadb"  => "mariadb:import",
        "mongodb"  => "mongo:import",
        "redis"    => "redis:import"
      )
    end
  end

  describe "#perform!" do
    it "raises UnsupportedTypeError for a service type with no import command" do
      service = build_service(db_type: "cassandra")
      expect { service.perform! }.to raise_error(
        ImportService::UnsupportedTypeError, /No import command for cassandra/
      )
    end

    it "runs the bare import command when ssh_user is dokku" do
      service = build_service(db_type: "postgres", ssh_user: "dokku", name: "pg-main")
      executed = []
      channel = build_mock_ssh_channel(executed)

      with_stubbed_ssh(channel) { service.perform! }

      expect(executed).to eq([ "postgres:import pg-main" ])
    end

    it "uses the per-type command for mysql" do
      service = build_service(db_type: "mysql", ssh_user: "dokku", name: "my-db")
      executed = []
      channel = build_mock_ssh_channel(executed)

      with_stubbed_ssh(channel) { service.perform! }

      expect(executed).to eq([ "mysql:import my-db" ])
    end

    it "maps mongodb to the mongo:import command" do
      service = build_service(db_type: "mongodb", ssh_user: "dokku", name: "mongo-db")
      executed = []
      channel = build_mock_ssh_channel(executed)

      with_stubbed_ssh(channel) { service.perform! }

      expect(executed).to eq([ "mongo:import mongo-db" ])
    end

    it "prepends 'dokku' to the command when ssh_user is not dokku" do
      service = build_service(db_type: "postgres", ssh_user: "ubuntu", name: "pg-main")
      executed = []
      channel = build_mock_ssh_channel(executed)

      with_stubbed_ssh(channel) { service.perform! }

      expect(executed).to eq([ "dokku postgres:import pg-main" ])
    end

    it "falls back to the dokku ssh_user when server.ssh_user is nil" do
      service = build_service(db_type: "postgres", ssh_user: nil, name: "pg-main")
      executed = []
      channel = build_mock_ssh_channel(executed)

      captured = nil
      with_stubbed_ssh(channel) { |c| service.perform!; captured = c }

      expect(executed).to eq([ "postgres:import pg-main" ])
      expect(captured[:user]).to eq("dokku")
    end

    it "shell-escapes the database name" do
      service = build_service(db_type: "postgres", ssh_user: "dokku", name: "weird name;rm")
      executed = []
      channel = build_mock_ssh_channel(executed)

      with_stubbed_ssh(channel) { service.perform! }

      expect(executed.first).to eq("postgres:import #{Shellwords.escape('weird name;rm')}")
    end

    it "streams the dump in 64KB chunks and signals EOF" do
      big = "x" * (64 * 1024 + 100) # forces a second read iteration
      service = build_service(db_type: "postgres", ssh_user: "dokku", dump: big)
      sent = []
      channel = build_mock_ssh_channel([], sent_chunks: sent)

      with_stubbed_ssh(channel) { service.perform! }

      expect(sent.length).to eq(2)
      expect(sent.first.bytesize).to eq(64 * 1024)
      expect(sent.join).to eq(big)
    end

    it "connects with the server host, user, and ssh options" do
      service = build_service(db_type: "postgres", ssh_user: "dokku", port: 2222)
      channel = build_mock_ssh_channel([])

      captured = nil
      with_stubbed_ssh(channel) { |c| service.perform!; captured = c }

      expect(captured[:host]).to eq("10.0.0.1")
      expect(captured[:user]).to eq("dokku")
      expect(captured[:opts][:port]).to eq(2222)
      expect(captured[:opts][:non_interactive]).to eq(true)
      expect(captured[:opts][:timeout]).to eq(10)
    end

    it "defaults the ssh port to 22 when server.port is nil" do
      service = build_service(db_type: "postgres", ssh_user: "dokku", port: nil)
      channel = build_mock_ssh_channel([])

      captured = nil
      with_stubbed_ssh(channel) { |c| service.perform!; captured = c }

      expect(captured[:opts][:port]).to eq(22)
    end

    it "passes key_data when the server has a private key" do
      key = "-----BEGIN RSA PRIVATE KEY-----\ntest\n-----END RSA PRIVATE KEY-----"
      service = build_service(db_type: "postgres", ssh_user: "dokku", ssh_key: key)
      channel = build_mock_ssh_channel([])

      captured = nil
      with_stubbed_ssh(channel) { |c| service.perform!; captured = c }

      expect(captured[:opts][:key_data]).to eq([ key ])
    end

    it "omits key_data when the server has no private key" do
      service = build_service(db_type: "postgres", ssh_user: "dokku", ssh_key: nil)
      channel = build_mock_ssh_channel([])

      captured = nil
      with_stubbed_ssh(channel) { |c| service.perform!; captured = c }

      expect(captured[:opts]).not_to have_key(:key_data)
    end

    it "raises when the remote command fails to start" do
      service = build_service(db_type: "postgres", ssh_user: "dokku")
      channel = build_mock_ssh_channel([], exec_success: false)

      expect {
        with_stubbed_ssh(channel) { service.perform! }
      }.to raise_error(RuntimeError, /Failed to execute import command/)
    end
  end
end

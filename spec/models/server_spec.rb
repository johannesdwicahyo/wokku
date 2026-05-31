require "rails_helper"

RSpec.describe Server do
  let(:owner) { User.create!(email: "server-owner@example.com", password: "password123456") }
  let(:team)  { Team.create!(name: "server-team", owner: owner) }

  it "is valid" do
    server = Server.new(name: "web-1", host: "10.0.0.1", team: team)
    expect(server).to be_valid
  end

  it "requires name" do
    server = Server.new(host: "10.0.0.1", team: team)
    expect(server).not_to be_valid
    expect(server.errors[:name]).to include("can't be blank")
  end

  it "requires host" do
    server = Server.new(name: "web-1", team: team)
    expect(server).not_to be_valid
    expect(server.errors[:host]).to include("can't be blank")
  end

  it "name is unique within team" do
    Server.create!(name: "web-1", host: "10.0.0.1", team: team)
    duplicate = Server.new(name: "web-1", host: "10.0.0.2", team: team)
    expect(duplicate).not_to be_valid
  end

  it "defaults to port 22 and ssh_user dokku" do
    server = Server.new(name: "web-1", host: "10.0.0.1", team: team)
    expect(server.port).to eq(22)
    expect(server.ssh_user).to eq("dokku")
  end

  it "default status is connected" do
    server = Server.new(name: "web-1", host: "10.0.0.1", team: team)
    expect(server.status).to eq("connected")
  end

  it "encrypts ssh_private_key" do
    server = Server.create!(name: "enc-test", host: "10.0.0.1", team: team, ssh_private_key: "secret-key-data")
    server.reload
    expect(server.ssh_private_key).to eq("secret-key-data")
  end

  it "port must be positive integer" do
    server = Server.new(name: "web-1", host: "10.0.0.1", team: team, port: -1)
    expect(server).not_to be_valid
    expect(server.errors[:port]).to include("must be greater than 0")
  end

  describe "platform-owned BackupDestination" do
    ENV_VARS_FOR_BACKUP = %w[
      WOKKU_TENANT_BACKUP_S3_BUCKET
      WOKKU_TENANT_BACKUP_S3_ENDPOINT
      WOKKU_TENANT_BACKUP_S3_ACCESS_KEY_ID
      WOKKU_TENANT_BACKUP_S3_SECRET_ACCESS_KEY
    ].freeze

    def with_backup_env(values)
      original = ENV_VARS_FOR_BACKUP.to_h { |k| [ k, ENV[k] ] }
      values.each { |k, v| ENV[k] = v }
      yield
    ensure
      original.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    end

    it "creates a destination when env is set" do
      with_backup_env(
        "WOKKU_TENANT_BACKUP_S3_BUCKET"        => "wokku-dataplane",
        "WOKKU_TENANT_BACKUP_S3_ENDPOINT"      => "https://example.r2.cloudflarestorage.com",
        "WOKKU_TENANT_BACKUP_S3_ACCESS_KEY_ID" => "akid",
        "WOKKU_TENANT_BACKUP_S3_SECRET_ACCESS_KEY" => "secret"
      ) do
        server = Server.create!(name: "plat-backup-test", host: "10.0.0.99", team: team)
        expect(server.backup_destination).to be_present
        dest = server.backup_destination
        expect(dest.bucket).to eq("wokku-dataplane")
        expect(dest.path_prefix).to eq("dbs/plat-backup-test")
        expect(dest.provider).to eq("r2")
        expect(dest.enabled?).to be true
      end
    end

    it "no-ops when env is unset" do
      with_backup_env(ENV_VARS_FOR_BACKUP.to_h { |k| [ k, nil ] }) do
        server = Server.create!(name: "no-env-test", host: "10.0.0.88", team: team)
        expect(server.backup_destination).to be_nil
      end
    end
  end
end

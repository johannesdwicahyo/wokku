# frozen_string_literal: true

require "rails_helper"

RSpec.describe DatabaseProvisioner do
  let(:stub_client_class) do
    Class.new do
      attr_reader :calls, :stdin_calls

      def initialize
        @calls = []
        @stdin_calls = []
      end

      def run(cmd, timeout: 30, stdin: nil)
        @calls << cmd
        @stdin_calls << stdin if stdin
        ""
      end
    end
  end

  let(:app) { app_records(:one) }
  let(:client) { stub_client_class.new }

  it "dedicated tier provisions via Dokku::Databases and links to app", skip: "see DatabaseProvisioner deep spec follow-up" do
    provisioner = described_class.new(
      app: app, service_type: "postgres", tier: "mini", client: client
    )

    db = nil
    expect {
      db = provisioner.call
    }.to change { DatabaseService.count }.by(1)
      .and change { AppDatabase.count }.by(1)

    expect(db.shared?).to be_falsey
    expect(db.tier_name).to eq("mini")
    expect(client.calls.any? { |c| c.start_with?("postgres:create") }).to be_truthy
    expect(client.calls.any? { |c| c.start_with?("postgres:link") }).to be_truthy
  end

  it "shared_free tier routes through Dokku::SharedPostgres and sets DATABASE_URL via config", skip: "see DatabaseProvisioner deep spec follow-up" do
    provisioner = described_class.new(
      app: app, service_type: "postgres", tier: "shared_free", client: client
    )

    db = nil
    expect {
      db = provisioner.call
    }.to change { DatabaseService.count }.by(2)
      .and change { AppDatabase.count }.by(1)

    expect(db.shared?).to be_truthy
    expect(db.tier_name).to eq("shared_free")
    expect(db.shared_role_name).to match(/\Au_/)
    expect(db.shared_db_name).to match(/\Adb_/)
    expect(db.storage_mb_quota).to eq(150)
    expect(db.connection_limit).to eq(5)

    expect(client.calls.any? { |c| c.include?("config:set") }).to be_truthy
    expect(db.parent_service.name).to eq("wokku-shared-free")
  end

  it "shared_free tier is postgres-only (mysql falls through to dedicated)" do
    provisioner = described_class.new(
      app: app, service_type: "mysql", tier: "shared_free", client: client
    )
    db = provisioner.call
    expect(db.shared?).to be_falsey
    expect(client.stdin_calls.any? { |s| s.to_s.include?("CREATE ROLE") }).to be_falsey
  end

  it "destroy! for shared tenant tears down role + db via SharedPostgres", skip: "see DatabaseProvisioner deep spec follow-up" do
    db = described_class.new(
      app: app, service_type: "postgres", tier: "shared_free", client: client
    ).call
    client.calls.clear
    client.stdin_calls.clear

    described_class.destroy!(database_service: db, client: client)

    expect(client.stdin_calls.any? { |s| s.include?("DROP DATABASE") }).to be_truthy
    expect(client.stdin_calls.any? { |s| s.include?("DROP ROLE") }).to be_truthy
    expect(client.calls.any? { |c| c.include?("config:unset") && c.include?("DATABASE_URL") }).to be_truthy
  end

  it "destroy! for dedicated calls Dokku::Databases.destroy" do
    db = described_class.new(
      app: app, service_type: "postgres", tier: "mini", client: client
    ).call
    client.calls.clear

    described_class.destroy!(database_service: db, client: client)

    expect(client.calls.any? { |c| c.start_with?("postgres:destroy") }).to be_truthy
  end
end

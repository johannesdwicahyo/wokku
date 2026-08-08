# frozen_string_literal: true

require "rails_helper"

RSpec.describe BackupSchedulerJob, type: :job do
  describe "BACKUPABLE_TYPES" do
    it "covers durable database types plus redis (RDB snapshot, since 2026-07-15)" do
      expect(described_class::BACKUPABLE_TYPES).to match_array(%w[postgres mysql mariadb mongodb redis])
    end

    it "EXCLUDES memcached/valkey (no export path)" do
      %w[memcached valkey].each do |cache|
        expect(described_class::BACKUPABLE_TYPES).not_to include(cache),
          "#{cache} has no export path and must not be auto-backed up"
      end
    end
  end

  describe "BackupService::EXPORT_COMMANDS alignment" do
    it "has no command for exportless cache types" do
      %w[memcached valkey].each do |cache|
        expect(BackupService::EXPORT_COMMANDS).not_to have_key(cache)
      end
    end

    it "has a command for every BACKUPABLE_TYPE" do
      described_class::BACKUPABLE_TYPES.each do |t|
        expect(BackupService::EXPORT_COMMANDS).to have_key(t),
          "BACKUPABLE_TYPES includes #{t} but BackupService::EXPORT_COMMANDS does not"
      end
    end
  end

  describe ".perform_now / enqueueing" do
    it "can be enqueued" do
      expect { described_class.perform_later }.to have_enqueued_job(described_class)
    end

    it "enqueues BackupJob for each running database with a backup destination" do
      server = servers(:one)
      destination = BackupDestination.create!(
        server: server, bucket: "test-bucket", region: "us-east-1",
        access_key_id: "AKID", secret_access_key: "secret",
        enabled: true, retention_days: 7, path_prefix: "backups"
      )
      ServiceTier.find_or_create_by!(name: "standard", service_type: "postgres") do |t|
        t.price_cents_per_hour = 0.274
        t.spec = { storage_gb: 4, connections: 50 }
      end
      DatabaseService.create!(
        server: server, service_type: "postgres",
        name: "pg-scheduler-test", status: :running, tier_name: "standard"
      )

      expect { described_class.perform_now }.to have_enqueued_job(BackupJob).at_least(:once)
    ensure
      destination&.destroy
    end

    it "does not enqueue BackupJob when no enabled backup destinations" do
      BackupDestination.where(enabled: true).destroy_all
      expect { described_class.perform_now }.not_to have_enqueued_job(BackupJob)
    end

    it "enqueues BackupJob for a running dedicated redis, but NOT a shared_free redis tenant" do
      server = servers(:one)
      destination = BackupDestination.create!(
        server: server, bucket: "test-bucket", region: "us-east-1",
        access_key_id: "AKID", secret_access_key: "secret",
        enabled: true, retention_days: 7, path_prefix: "backups"
      )
      ServiceTier.find_or_create_by!(name: "shared_free", service_type: "redis") do |t|
        t.price_cents_per_hour = 0
        t.spec = {}
      end
      dedicated = DatabaseService.create!(
        server: server, service_type: "redis",
        name: "redis-dedicated-test", status: :running, tier_name: "basic"
      )
      parent = DatabaseService.create!(
        server: server, service_type: "redis",
        name: "dokku-shared-redis", status: :running, tier_name: "shared_host"
      )
      shared_tenant = DatabaseService.create!(
        server: server, service_type: "redis",
        name: "redis-shared-tenant", status: :running, tier_name: "shared_free",
        shared: true, parent_service: parent
      )

      expect { described_class.perform_now }.to have_enqueued_job(BackupJob).with(dedicated.id)
      expect { described_class.perform_now }.not_to have_enqueued_job(BackupJob).with(shared_tenant.id)
      expect { described_class.perform_now }.not_to have_enqueued_job(BackupJob).with(parent.id)
    ensure
      destination&.destroy
    end

    it "does NOT back up the shared-host parent container (tier=shared_host infra; export always fails)" do
      server = servers(:one)
      destination = BackupDestination.create!(
        server: server, bucket: "test-bucket", region: "us-east-1",
        access_key_id: "AKID", secret_access_key: "secret",
        enabled: true, retention_days: 7, path_prefix: "backups"
      )
      shared_host = DatabaseService.create!(
        server: server, service_type: "postgres",
        name: "dokku-shared-postgres", status: :running, tier_name: "shared_host"
      )

      expect { described_class.perform_now }.not_to have_enqueued_job(BackupJob).with(shared_host.id)
    ensure
      destination&.destroy
    end
  end

  describe "volume backup scheduling" do
    it "enqueues VolumeBackupJob for paid-plan apps and skips free-plan apps" do
      server = servers(:one)
      destination = BackupDestination.create!(
        server: server, bucket: "test-bucket", region: "us-east-1",
        access_key_id: "AKID", secret_access_key: "secret",
        enabled: true, retention_days: 7, path_prefix: "backups"
      )
      paid_app = create(:app_record, server: server, team: teams(:one))
      free_app = create(:app_record, server: server, team: teams(:one))

      allow_any_instance_of(AppRecord).to receive(:owner_plan) do |app|
        app.id == paid_app.id ? plans(:solo) : plans(:free)
      end

      expect { described_class.perform_now }.to have_enqueued_job(VolumeBackupJob).with(paid_app.id)
      expect { described_class.perform_now }.not_to have_enqueued_job(VolumeBackupJob).with(free_app.id)
    ensure
      destination&.destroy
    end

    it "does NOT enqueue VolumeBackupJob for preview apps even if owner has paid plan" do
      server = servers(:one)
      destination = BackupDestination.create!(
        server: server, bucket: "test-bucket", region: "us-east-1",
        access_key_id: "AKID", secret_access_key: "secret",
        enabled: true, retention_days: 7, path_prefix: "backups"
      )
      parent_app = create(:app_record, server: server, team: teams(:one))
      preview_app = create(:app_record, server: server, team: teams(:one), is_preview: true, parent_app: parent_app, pr_number: 42)

      allow_any_instance_of(AppRecord).to receive(:owner_plan) do |app|
        plans(:solo) # both have paid plan
      end

      expect { described_class.perform_now }.not_to have_enqueued_job(VolumeBackupJob).with(preview_app.id)
    ensure
      destination&.destroy
    end
  end
end

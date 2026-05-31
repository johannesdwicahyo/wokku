# frozen_string_literal: true

require "rails_helper"

RSpec.describe BackupSchedulerJob, type: :job do
  describe "BACKUPABLE_TYPES" do
    it "covers durable database types" do
      expect(described_class::BACKUPABLE_TYPES).to match_array(%w[postgres mysql mariadb mongodb])
    end

    it "EXCLUDES cache-type services by policy" do
      %w[redis memcached valkey].each do |cache|
        expect(described_class::BACKUPABLE_TYPES).not_to include(cache),
          "#{cache} is a cache type and must not be auto-backed up"
      end
    end
  end

  describe "BackupService::EXPORT_COMMANDS alignment" do
    it "has no command for cache types" do
      %w[redis memcached valkey].each do |cache|
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
  end
end

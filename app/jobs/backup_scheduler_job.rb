class BackupSchedulerJob < ApplicationJob
  queue_as :backups

  # redis included since 2026-07-15: customers use it as a store (queues,
  # sessions), not just a cache — an RDB snapshot beats nothing. memcached
  # stays excluded (no export path, genuinely ephemeral). Shared redis
  # tenants are shared_free tier (auto_backup: false) so only dedicated
  # services get the nightly export.
  BACKUPABLE_TYPES = %w[postgres mysql mariadb mongodb redis].freeze

  def perform
    Server.joins(:backup_destination)
      .where(backup_destinations: { enabled: true })
      .find_each do |server|
        server.database_services
          .where(service_type: BACKUPABLE_TYPES, status: :running)
          # The shared-host parent container (dokku-shared-postgres, tier=shared_host)
          # is infra, not a user DB — postgres:export on it always fails. IS DISTINCT
          # FROM keeps NULL-tier rows in scope.
          .where("database_services.tier_name IS DISTINCT FROM ?", "shared_host")
          .find_each do |db|
            next unless db.auto_backup?
            BackupJob.perform_later(db.id)
          end

        # Volume backups: paid-plan apps only (founder-locked 2026-07-15);
        # the job itself no-ops for apps with no declared mounts.
        server.app_records.find_each do |app|
          next if app.is_preview? # previews are throwaway
          next if app.owner_plan.nil? || app.owner_plan.free?
          VolumeBackupJob.perform_later(app.id)
        end
      end
  end
end

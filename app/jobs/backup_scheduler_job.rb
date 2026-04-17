class BackupSchedulerJob < ApplicationJob
  queue_as :backups

  BACKUPABLE_TYPES = %w[postgres mysql mariadb mongodb redis].freeze

  def perform
    Server.joins(:backup_destination)
      .where(backup_destinations: { enabled: true })
      .find_each do |server|
        server.database_services
          .where(service_type: BACKUPABLE_TYPES, status: :running)
          .find_each do |db|
            next unless db.auto_backup?
            BackupJob.perform_later(db.id)
          end
      end
  end
end

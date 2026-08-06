require "set"

class BackupRetentionJob < ApplicationJob
  queue_as :backups

  VOLUME_GFS = { daily: 7, weekly: 0, monthly: 0 }.freeze # founder-locked 2026-07-15

  def perform
    DatabaseService.where(status: :running).find_each do |db|
      gfs = db.backup_policy[:gfs] || { daily: 0, weekly: 0, monthly: 0 }
      next if gfs.values.all? { |v| v.to_i.zero? } # shared_free: no scheduled backups, never delete

      keep = gfs_keep_ids(db.backups.where(status: "completed").order(created_at: :desc), gfs)
      next if keep.empty? # defense-in-depth: empty keep-set must never mean "delete everything"
      deleted = 0
      db.backups.where(status: "completed").where.not(id: keep.to_a).find_each do |backup|
        deleted += 1 if delete_backup(backup)
      end
      Rails.logger.info("[BackupRetentionJob] #{db.name}: deleted #{deleted}, kept #{keep.size}") if deleted.positive?
    end

    Backup.kind_volume.where(status: "completed")
      .distinct.pluck(:app_record_id, :mount_path).each do |app_id, mount|
      next if app_id.nil? # defensive: never delete on a null-keyed group (FK on_delete: :nullify edge case)

      scope = Backup.kind_volume.where(app_record_id: app_id, mount_path: mount, status: "completed")
      keep = gfs_keep_ids(scope.order(created_at: :desc), VOLUME_GFS)
      next if keep.empty? # defense-in-depth: empty keep-set must never mean "delete everything"
      deleted = 0
      scope.where.not(id: keep.to_a).find_each { |backup| deleted += 1 if delete_backup(backup) }
      label = AppRecord.find_by(id: app_id)&.name || app_id
      Rails.logger.info("[BackupRetentionJob] volume #{label}/#{mount}: deleted #{deleted}, kept #{keep.size}") if deleted.positive?
    end
  end

  private

  # Keep one backup per calendar day for the last `daily` days, one per ISO
  # week for `weekly` weeks, one per calendar month for `monthly` months —
  # walking newest first. A backup can satisfy several buckets at once; the
  # Set dedupes. Loaded in memory (not find_each): the walk order must be
  # newest-first by created_at, and find_each forces its own batch (id)
  # order, which would silently scramble the GFS math since backup ids are
  # uuidv7 (insertion order), not created_at order.
  def gfs_keep_ids(backups, gfs)
    keep = Set.new
    days = {}
    weeks = {}
    months = {}

    backups.each do |backup|
      date = backup.created_at.to_date
      week = date.strftime("%G-%V")
      month = date.strftime("%Y-%m")

      unless days.key?(date)
        days[date] = true
        keep << backup.id if days.size <= gfs[:daily].to_i
      end

      unless weeks.key?(week)
        weeks[week] = true
        keep << backup.id if weeks.size <= gfs[:weekly].to_i
      end

      unless months.key?(month)
        months[month] = true
        keep << backup.id if months.size <= gfs[:monthly].to_i
      end
    end

    keep
  end

  def delete_backup(backup)
    dest = backup.backup_destination
    dest.s3_client.delete_object(bucket: dest.bucket, key: backup.s3_key)
    backup.destroy!
    Rails.logger.info("BackupRetentionJob: Deleted backup #{backup.s3_key}")
    true
  rescue => e
    Rails.logger.error("BackupRetentionJob: Failed to delete #{backup.s3_key}: #{e.message}")
    false
  end
end

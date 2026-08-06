class Backup < ApplicationRecord
  belongs_to :database_service, optional: true
  belongs_to :app_record, optional: true
  belongs_to :backup_destination

  enum :kind, { database: 0, volume: 1 }, prefix: true

  # on: :create — a farewell snapshot (DatabaseService's pre-destroy hook)
  # detaches itself from the dying service so its FK doesn't block the
  # DELETE; the detached row must stay updatable as the surviving restore
  # artifact.
  validates :database_service, presence: true, if: :kind_database?, on: :create
  validates :app_record, presence: true, if: :kind_volume?
  validates :mount_path, presence: true, if: :kind_volume?

  scope :completed, -> { where(status: "completed") }
  scope :in_flight, -> { where(status: %w[pending running]) }
  scope :recent, -> { order(created_at: :desc).limit(20) }

  # Live-update the Backup Now button + backups table when a backup's
  # status flips so users see the row change Pending → Running → Completed
  # without refreshing, and the action button frame returns to ready.
  # Volume backups don't have a Turbo stream target yet (Task 3+) — guard
  # to kind_database? so we don't touch database_service on nil.
  # The database_service presence guards cover farewell snapshots: they
  # detach from the dying service inside the destroy transaction, so by
  # commit time there is no service (or dashboard stream) to render for.
  after_create_commit  :broadcast_actions_frame, if: -> { kind_database? && database_service }
  after_update_commit  :broadcast_status_change, if: -> { kind_database? && database_service && saved_change_to_status? }

  def stream_name
    "database_#{database_service_id}_backups"
  end

  def broadcast_actions_frame
    Turbo::StreamsChannel.broadcast_replace_to(
      stream_name,
      target: "backup_actions",
      partial: "dashboard/backups/actions",
      locals: { database: database_service }
    )
  end

  def broadcast_status_change
    broadcast_actions_frame
    Turbo::StreamsChannel.broadcast_refresh_later_to(stream_name)
    case status.to_s
    when "completed"
      database_service.broadcast_backup_toast(level: "success", message: "#{database_service.name}: backup complete (#{size_human}).")
    when "failed"
      msg = error_message.to_s.lines.first&.strip || "see backups page"
      database_service.broadcast_backup_toast(level: "error", message: "#{database_service.name}: backup failed — #{msg.to_s.truncate(120)}")
    end
  end

  def duration
    return nil unless started_at && completed_at
    completed_at - started_at
  end

  def size_human
    return "—" unless size_bytes
    if size_bytes < 1024
      "#{size_bytes} B"
    elsif size_bytes < 1024 * 1024
      "#{(size_bytes / 1024.0).round(1)} KB"
    elsif size_bytes < 1024 * 1024 * 1024
      "#{(size_bytes / (1024.0 * 1024)).round(1)} MB"
    else
      "#{(size_bytes / (1024.0 * 1024 * 1024)).round(2)} GB"
    end
  end

  def download_url(expires_in: 3600)
    backup_destination.s3_presigned_url(s3_key, expires_in: expires_in)
  end

  def expired?(retention_days = nil)
    days = retention_days || backup_destination.retention_days
    created_at < days.days.ago
  end
end

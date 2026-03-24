class Backup < ApplicationRecord
  belongs_to :database_service
  belongs_to :backup_destination

  scope :completed, -> { where(status: "completed") }
  scope :recent, -> { order(created_at: :desc).limit(20) }

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

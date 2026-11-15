# One RustFS -> R2 backup report (nightly sync or weekly drill) POSTed by the
# host script. `error` may accompany an ok run (e.g. drill with nothing to sample).
class StorageBackupRun < ApplicationRecord
  TZ = "Asia/Jakarta".freeze

  belongs_to :server

  validates :kind, inclusion: { in: %w[sync drill] }
  validates :status, inclusion: { in: %w[ok failed] }

  scope :sync_runs, -> { where(kind: "sync") }

  # Consecutive Jakarta calendar days (newest first) with an ok sync and no
  # failed sync. Counting starts at the most recent day that has a run, so a
  # not-yet-run today doesn't break the streak.
  def self.green_streak(server)
    days = server.storage_backup_runs.sync_runs.order(created_at: :desc)
      .pluck(:created_at, :status)
      .group_by { |t, _| t.in_time_zone(TZ).to_date }
    return 0 if days.empty?

    day = days.keys.max
    streak = 0
    while (runs = days[day]) && runs.any? { |_, s| s == "ok" } && runs.none? { |_, s| s == "failed" }
      streak += 1
      day -= 1
    end
    streak
  end

  def self.last_drill_ok?(server)
    server.storage_backup_runs.where(kind: "drill").order(:created_at).last&.status == "ok"
  end
end

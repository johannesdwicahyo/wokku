class ServiceTier < ApplicationRecord
  HOURS_PER_MONTH = 720

  # Backup policies per tier (Option C', adopted 2026-05-15).
  # Premise: production data is always protected; tier controls retention
  # depth, not whether backups happen at all. Cost on R2 is small enough
  # (~$0.02-0.27/DB/month at typical sizes) that bundling beats forcing
  # an upgrade to get any safety net.
  #
  # - shared_free: no scheduled auto-backup, but takes a one-shot snapshot
  #                on destroy so the user has a recovery file in R2 for
  #                30 days after deleting a free-tier service. "Backup now"
  #                works free_cap times a day; retention keeps the newest
  #                free_cap.
  # - basic:       daily auto, 7 dailies kept, no weekly/monthly.
  # - standard:    daily auto, 7 dailies + 4 weeklies + 1 monthly (GFS).
  # - performance: daily auto, 7 dailies + 4 weeklies + 3 monthlies (GFS).
  #
  # GFS (grandfather-father-son) numbers are founder-locked (2026-07-14
  # backup hardening spec) — do not adjust without re-confirming.
  #
  # memcached is excluded upstream in BackupSchedulerJob::BACKUPABLE_TYPES
  # regardless of tier (no export path). redis IS backed up (RDB snapshot)
  # since 2026-07-15 — customers use it as a store, not just a cache.
  BACKUP_POLICIES = {
    "shared_free" => { auto_backup: false, gfs: { daily: 0, weekly: 0, monthly: 0 }, on_destroy_snapshot: true,  free_cap: 2 },
    "basic"       => { auto_backup: true,  gfs: { daily: 7, weekly: 0, monthly: 0 }, on_destroy_snapshot: false, free_cap: nil },
    "standard"    => { auto_backup: true,  gfs: { daily: 7, weekly: 4, monthly: 1 }, on_destroy_snapshot: false, free_cap: nil },
    "performance" => { auto_backup: true,  gfs: { daily: 7, weekly: 4, monthly: 3 }, on_destroy_snapshot: false, free_cap: nil }
  }.freeze

  validates :name, presence: true
  validates :service_type, presence: true
  validates :price_cents_per_hour, numericality: { greater_than_or_equal_to: 0 }
  validates :name, uniqueness: { scope: :service_type }

  scope :available, -> { where(available: true) }
  scope :for_type, ->(type) { where(service_type: type) }

  def free?
    monthly_price_cents.to_i == 0
  end

  # Pricing model: monthly_price_cents is the source of truth.
  # Hourly = monthly / 720; daily = monthly / 30. The daily-deduction
  # job caps cumulative billing at 720h/month so a 31-day month never
  # overcharges (28-day Feb bills 28 × daily, not the full monthly).
  def monthly_price_dollars
    monthly_price_cents / 100.0
  end

  def hourly_price_cents
    monthly_price_cents.to_f / HOURS_PER_MONTH
  end

  def daily_price_cents
    monthly_price_cents.to_f / 30.0
  end

  def backup_policy
    BACKUP_POLICIES[name] || BACKUP_POLICIES["basic"]
  end

  def auto_backup?
    backup_policy[:auto_backup]
  end

  def gfs_policy
    backup_policy[:gfs]
  end

  def free_backup_cap
    backup_policy[:free_cap]
  end
end

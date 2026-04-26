class DedicatedDatabaseQuotaJob < ApplicationJob
  queue_as :default

  # Soft enforcement on dedicated postgres services. Mirrors
  # SharedDatabaseQuotaJob but reads live_db_bytes (populated by
  # MetricsPollJob each minute) instead of running its own SSH probe.
  #
  # 80% → set over_quota_at (UI surfaces a warning banner, notification
  # fires once)
  # 100% + 24h grace → set status=:stopped (UI dimmed, write revocation
  # is platform-policy and not enforced at the postgres layer because
  # dokku-postgres exposes the superuser; the stop signal is advisory).
  GRACE_PERIOD = 24.hours

  def perform
    DatabaseService.where(shared: false, service_type: "postgres").find_each do |db|
      enforce(db)
    end
  end

  private

  def enforce(db)
    tier = db.service_tier
    storage_gb = tier&.spec&.fetch("storage_gb", nil) || tier&.spec&.dig(:storage_gb)
    return unless storage_gb && storage_gb.to_i.positive?
    return unless db.live_db_bytes

    cap_bytes = storage_gb.to_i * 1_024 * 1_024 * 1_024
    used = db.live_db_bytes
    pct = (used.to_f / cap_bytes * 100).round(1)

    if used >= cap_bytes
      handle_full(db)
    elsif pct >= 80
      handle_warning(db, pct)
    elsif db.over_quota?
      handle_recovered(db)
    end
  rescue StandardError => e
    Rails.logger.warn "DedicatedDatabaseQuotaJob: #{db.name} failed: #{e.message}"
  end

  def handle_warning(db, pct)
    return if db.over_quota_at.present? # already warned
    db.update!(over_quota_at: Time.current)
    Rails.logger.info "Dedicated DB #{db.name} at #{pct}% — quota warning"
    notify(db, pct: pct, level: :warning)
  end

  def handle_full(db)
    if db.over_quota_at.blank?
      db.update!(over_quota_at: Time.current)
      Rails.logger.info "Dedicated DB #{db.name} reached 100% — grace period begins"
      notify(db, pct: 100, level: :critical)
    elsif db.over_quota_at < GRACE_PERIOD.ago && db.status != "stopped"
      db.update!(status: :stopped)
      Rails.logger.info "Dedicated DB #{db.name} flagged stopped after 24h over quota"
      notify(db, pct: 100, level: :stopped)
    end
  end

  def handle_recovered(db)
    db.update!(over_quota_at: nil)
    Rails.logger.info "Dedicated DB #{db.name} back under quota — warning cleared"
  end

  def notify(db, pct:, level:)
    return unless defined?(Activity)
    creator = db.app_records.first&.creator
    team = db.app_records.first&.team
    return unless creator && team
    Activity.log(
      user: creator, team: team, action: "database.quota_#{level}",
      target: db, metadata: { pct: pct, name: db.name, tier: db.tier_name }
    )
  rescue StandardError => e
    Rails.logger.warn "DedicatedDatabaseQuotaJob: notify failed: #{e.message}"
  end
end

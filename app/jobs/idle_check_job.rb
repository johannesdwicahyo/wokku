class IdleCheckJob < ApplicationJob
  queue_as :default

  IDLE_THRESHOLD = 30.minutes

  def perform
    eco_tier = DynoTier.find_by(name: "eco")
    return unless eco_tier

    eco_apps = AppRecord.running.joins(:dyno_allocations)
      .where(dyno_allocations: { dyno_tier_id: eco_tier.id })
      .distinct

    eco_apps.find_each do |app|
      last_request = app.metrics.order(recorded_at: :desc).first&.recorded_at
      next if last_request && last_request > IDLE_THRESHOLD.ago

      Lifecycle::Ops.converge!(app, formation: Lifecycle::Ops.stop_formation(app), allow_empty: true)
      app.sleeping!
    rescue Lifecycle::Ops::Failed, Lifecycle::Ops::Timeout, Lifecycle::Ops::Busy, ArgumentError => e
      Rails.logger.warn("IdleCheckJob: Failed to sleep #{app.name}: #{e.message}")
    end
  end
end

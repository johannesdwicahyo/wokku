module Apps
  # Per-app list stats (API apps.list, dashboard apps table): latest CPU and
  # memory from MetricsPollJob's live_* columns, plus 24h request counts from
  # RequestAggregate — one grouped query for the whole list.
  class ListStats
    # MetricsPollJob samples every minute; older live_* values mean the
    # collector can't see the app, so they'd be misleading.
    FRESH_FOR = 10.minutes

    def self.for(apps)
      requests = RequestAggregate.where(app_record_id: apps.map(&:id)).since(24.hours.ago)
                                 .group(:app_record_id).sum(:req_count)
      apps.to_h { |app| [ app.id, stats(app, requests[app.id].to_i) ] }
    end

    def self.stats(app, requests_24h)
      fresh = app.live_metrics_at&.after?(FRESH_FOR.ago)
      {
        cpu_pct: fresh ? app.live_cpu_pct&.to_f : nil,
        mem_mb: fresh ? app.live_mem_used_mb : nil,
        mem_limit_mb: fresh ? app.live_mem_limit_mb : nil,
        requests_24h: requests_24h,
        as_of: fresh ? app.live_metrics_at : nil
      }
    end

    # "18% · 410 MB · 4.2k req/24h"; unknown parts are left out.
    def self.summary(stats)
      [
        stats[:cpu_pct] && "#{stats[:cpu_pct].round}%",
        stats[:mem_mb] && "#{stats[:mem_mb]} MB",
        stats[:requests_24h].positive? && "#{ActiveSupport::NumberHelper.number_to_human(stats[:requests_24h], units: { thousand: "k", million: "M" }, format: "%n%u", precision: 2)} req/24h"
      ].select(&:itself).join(" · ").presence
    end
  end
end

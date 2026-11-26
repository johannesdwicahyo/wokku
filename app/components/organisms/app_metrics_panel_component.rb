module Organisms
  # "Metrics · last 24 h": CPU / Memory / Requests as 24 hourly light bars.
  class AppMetricsPanelComponent < ApplicationComponent
    STALE = 1.hour

    def initialize(stats:, now: Time.current)
      @stats = stats
      @now = now
    end

    def none = t("apps.detail.none")

    # "now" CPU is blank when the last sample is missing or older than an hour.
    def fresh? = @stats[:last_metric_at].present? && @stats[:last_metric_at] >= @now - STALE

    def rows
      s = @stats
      limit = s[:mem_limit_mb].to_i.positive? ? s[:mem_limit_mb] : 1
      req_max = [ Array(s[:req]).compact.max.to_f, 1 ].max
      [
        row(:cpu, s[:cpu], 100, (fresh? && s[:cpu_now]) ? "#{s[:cpu_now].round} %" : none),
        row(:memory, s[:mem], limit, s[:mem_now_mb] && s[:mem_limit_mb] ? t("apps.detail.metrics.memory_now", used: s[:mem_now_mb], limit: s[:mem_limit_mb]) : none),
        row(:requests, s[:req], req_max, s[:rpm_now] ? t("apps.detail.metrics.per_min", n: s[:rpm_now]) : none)
      ]
    end

    def ticks
      first = @now.beginning_of_hour - 23.hours
      [ first, first + 12.hours ].map { |h| h.strftime("%H:00") } + [ t("apps.detail.metrics.now") ]
    end

    private

    def row(key, values, max, now_text)
      name = t("apps.detail.metrics.#{key}")
      { name: name, now: now_text, values: Array(values), max: max, label: t("apps.detail.metrics.series", name: name) }
    end
  end
end

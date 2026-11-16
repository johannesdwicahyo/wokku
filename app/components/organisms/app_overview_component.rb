module Organisms
  class AppOverviewComponent < ApplicationComponent
    def initialize(app:)
      @app = app
    end
    attr_reader :app

    def memory_used_mb; app.live_mem_used_mb.to_i; end # heartbeat app_stats / MetricsPollJob
    def memory_max_mb;  app.dyno_allocations.first&.effective_memory_mb.to_i; end
    def memory_pct;     memory_max_mb.positive? ? (memory_used_mb * 100.0 / memory_max_mb).round : 0; end
    def size_label;     app.dyno_allocations.first&.size_label; end

    def recent_events
      # Activity points at its app polymorphically (no AppRecord#activities).
      Activity.where(target_type: "AppRecord", target_id: app.id).order(created_at: :desc).limit(8)
    end

    def display_url
      owned = Wokku.config.owned_domains
      custom = app.respond_to?(:domains) ? app.domains.find { |d| owned.none? { |z| d.hostname.to_s.end_with?(".#{z}") } } : nil
      host = custom&.hostname || "#{app.name}.#{Wokku.config.canonical_domain}"
      "https://#{host}"
    end
  end
end

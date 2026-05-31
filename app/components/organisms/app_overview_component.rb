module Organisms
  class AppOverviewComponent < ApplicationComponent
    def initialize(app:)
      @app = app
    end
    attr_reader :app

    def memory_used_mb; app.respond_to?(:memory_used_mb) ? app.memory_used_mb.to_i : 0; end
    def memory_max_mb;  app.dyno_allocations.first&.dyno_tier&.memory_mb.to_i; end
    def memory_pct;     memory_max_mb.positive? ? (memory_used_mb * 100.0 / memory_max_mb).round : 0; end

    def recent_events
      app.respond_to?(:activities) ? (app.activities.order(created_at: :desc).limit(8) rescue []) : []
    end

    def display_url
      owned = Cloudflare::Dns.owned_domains
      custom = app.respond_to?(:domains) ? app.domains.find { |d| owned.none? { |z| d.hostname.to_s.end_with?(".#{z}") } } : nil
      host = custom&.hostname || "#{app.name}.#{Cloudflare::Dns.canonical_domain}"
      "https://#{host}"
    end
  end
end

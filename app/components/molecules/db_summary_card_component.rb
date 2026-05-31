module Molecules
  class DbSummaryCardComponent < ApplicationComponent
    def initialize(app:)
      @app = app
      @db  = app.respond_to?(:primary_database) ? app.primary_database : nil
      @snapshot = @db&.stats_snapshots&.order(recorded_at: :desc)&.first
    end
    attr_reader :app, :db, :snapshot

    # Stats are sourced from the latest DatabaseStatsSnapshot — the live
    # `docker stats`-equivalent value collected by DatabaseStatsCollectorJob
    # every 5 minutes. When no snapshot exists yet (brand new DB, never
    # collected, free shared tenant) every reading degrades to 0 so the
    # card still renders.
    def usage_mb
      bytes = snapshot&.db_size_bytes.to_i
      bytes.zero? ? 0 : (bytes / 1024.0 / 1024.0).round(1)
    end

    def max_mb
      # Per-plan quota: prefer the shared tenant cap on free shared DBs,
      # otherwise fall back to 0 (unmeasured).
      db&.respond_to?(:size_mb_max) ? db.size_mb_max.to_i : 0
    end

    def pct
      max_mb.positive? ? (usage_mb * 100.0 / max_mb).round(1) : 0
    end

    def connections; snapshot&.active_connections.to_i; end
    def max_conn;    snapshot&.max_connections.to_i;    end
  end
end

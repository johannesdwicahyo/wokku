module Molecules
  class AddonSummaryCardComponent < ApplicationComponent
    def initialize(database_service:)
      @db = database_service
      @snapshot = db.stats_snapshots.order(recorded_at: :desc).first
    end
    attr_reader :db, :snapshot

    def label
      db.service_type.to_s.capitalize
    end

    def mode_label
      db.shared? ? "shared" : "dedicated"
    end

    def storage_used_mb
      bytes = snapshot&.db_size_bytes.to_i
      bytes.zero? ? 0 : (bytes / 1024.0 / 1024.0).round(1)
    end

    def storage_max_mb
      (db.service_tier&.spec || {})["storage_gb"].to_i * 1024
    end

    def storage_pct
      return 0 if storage_max_mb.zero?
      [ (storage_used_mb * 100.0 / storage_max_mb).round(1), 100 ].min
    end

    def connections
      snapshot&.active_connections.to_i
    end

    def max_connections
      snapshot&.max_connections.to_i.nonzero? ||
        (db.service_tier&.spec || {})["connections"].to_i
    end
  end
end

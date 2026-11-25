# frozen_string_literal: true

module Organisms
  # Apps page side column: Databases panel (max 5 add-ons, usage meter only
  # when the record carries used + allocated sizes).
  class AppsSideComponent < ApplicationComponent
    MAX = 5
    METER_SQUARES = 10

    def initialize(databases:, total: databases.size)
      @databases = databases
      @total = total
    end

    attr_reader :total

    def databases = @databases.first(MAX)

    def more? = total > MAX

    def state(db) = Organisms::CommandPaletteComponent.addon_state(db.status)

    def engine(db) = db.service_type.to_s.titleize

    # Allocated bytes: shared tenants carry a MB quota, dedicated ones a disk size.
    def allocated_bytes(db)
      mb = db.storage_mb_quota.presence || (db.disk_gb.to_i * 1024).presence
      mb && mb.megabytes
    end

    def meter?(db) = db.live_db_bytes.present? && allocated_bytes(db).to_i.positive?

    def meter_on(db) = (db.live_db_bytes.to_f / allocated_bytes(db) * METER_SQUARES).ceil

    def usage_text(db)
      t("apps.side.usage", used: number_to_human_size(db.live_db_bytes), total: number_to_human_size(allocated_bytes(db)))
    end

    # Calls the seam; never raises. Drops entries without a partial.
    def self.sections_for(view, team)
      Array.wrap(Wokku.config.apps_index_side_sections.call(view, team)).select { |s| s.is_a?(Hash) && s[:partial].present? }
    rescue StandardError => e
      Rails.logger.error("apps_index_side_sections failed: #{e.class}: #{e.message}")
      Sentry.capture_exception(e) if defined?(Sentry)
      []
    end
  end
end

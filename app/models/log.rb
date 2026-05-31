# A persisted Docker container log line, shipped from a Dokku host by
# Vector via `POST /api/v1/logs/ingest`. Source-of-truth for the
# searchable log history surfaced on `/dashboard/apps/:id/logs`.
#
# Today we use a single `logs` table for everyone — once a customer has
# multi-GB log volume we'll split per-server or move to ClickHouse, but
# Postgres handles 1-10 GB fine with the (app_record_id, ts DESC) index.
class Log < ApplicationRecord
  self.table_name = "logs"

  belongs_to :server
  belongs_to :app_record, optional: true

  validates :container, :ts, :line, presence: true

  LEVELS = %w[debug info warn error fatal].freeze

  scope :for_app, ->(app) { where(app_record_id: app.id) }
  scope :since,   ->(t)   { where("ts >= ?", t) }
  scope :until_,  ->(t)   { where("ts <= ?", t) }
  scope :at_level, ->(level) { where(level: level) if level.present? && LEVELS.include?(level) }
  scope :matching, ->(query) { where("line ILIKE ?", "%#{sanitize_sql_like(query)}%") if query.present? }
  scope :recent,  -> { order(ts: :desc) }

  # Detect the level from the line content if Vector didn't set it.
  # Heuristic — log formats vary wildly. Good enough for highlighting.
  LEVEL_PATTERNS = {
    "error" => /\b(ERROR|FATAL|CRITICAL|exception|panic|traceback)\b/i,
    "warn"  => /\b(WARN|WARNING)\b/i,
    "info"  => /\b(INFO|NOTICE)\b/i,
    "debug" => /\b(DEBUG|TRACE|VERBOSE)\b/i
  }.freeze

  def self.detect_level(line)
    LEVEL_PATTERNS.each { |level, pattern| return level if line.match?(pattern) }
    "info"
  end
end

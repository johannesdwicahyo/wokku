# frozen_string_literal: true

# Append-only outage record (Track A Phase 5) — one row per outage of a
# host (server_id) or an app (app_record_id), exactly one subject per row
# (DB check constraint), at most one open row per subject (partial unique
# indexes). Written on state TRANSITIONS by UptimeCheckJob (apps) and
# HostHeartbeatMonitorJob / Server#record_heartbeat! (hosts); the status
# page and its uptime % read from it.
class Incident < ApplicationRecord
  belongs_to :server, optional: true
  belongs_to :app_record, optional: true

  validates :reason, presence: true
  validates :started_at, presence: true

  scope :open, -> { where(resolved_at: nil) }
  scope :for_server, ->(server) { where(server: server) }

  def self.subject_key(subject)
    subject.is_a?(Server) ? :server : :app_record
  end

  def self.open_for(subject)
    open.find_by(subject_key(subject) => subject)
  end

  # Idempotent while an incident is open: monitor jobs run every minute
  # and must not stack rows for one ongoing outage.
  def self.open!(subject:, reason:, started_at: Time.current)
    open_for(subject) || create!(subject_key(subject) => subject, reason: reason, started_at: started_at)
  rescue ActiveRecord::RecordNotUnique
    open_for(subject)
  end

  def resolve!(at: Time.current)
    update!(resolved_at: at)
  end
end

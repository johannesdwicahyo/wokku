# frozen_string_literal: true

# One probe tick for one app (Track A Phase 5). Fan-out comes from
# UptimeCheckSchedulerJob every minute; this job owns the strike counter
# and the up/down transitions — 3 consecutive strikes open a typed
# Incident and notify the owner, the first success closes it. State
# writes use update_columns: a per-minute probe must not run
# validations/callbacks.
class UptimeCheckJob < ApplicationJob
  include Notifiable

  queue_as :uptime

  STRIKES = 3

  def perform(app_id)
    app = AppRecord.find_by(id: app_id)
    return unless app&.running?

    domain = app.domains.order(:created_at).first
    return unless domain

    result = Uptime::Probe.call("https://#{domain.hostname}/")
    # Serialize per-app transitions: with_lock reloads, so a racing tick
    # (at-least-once delivery, overlapping slow probe) sees the winner's
    # write and its was_down/already_down guard no-ops instead of
    # double-firing the owner notification. The probe stays outside the
    # lock — never hold a row lock across a 5s network call.
    app.with_lock do
      result.up? ? handle_up(app) : handle_strike(app, result)
    end
  end

  private

  def handle_up(app)
    was_down = app.uptime_status == "down"
    app.update_columns(uptime_status: "up", uptime_failures: 0, last_uptime_check_at: Time.current)
    return unless was_down

    incident = Incident.open_for(app)
    incident&.resolve!
    fire_team_event(app.team, "app_recovered", {
      app_name: app.name,
      reason: incident&.reason,
      since: incident&.started_at&.iso8601
    })
  end

  def handle_strike(app, result)
    failures = app.uptime_failures + 1
    already_down = app.uptime_status == "down"

    if failures >= STRIKES && !already_down
      classified = Uptime::ReasonClassifier.call(app, result.failure_kind)
      app.update_columns(uptime_status: "down", uptime_failures: failures, last_uptime_check_at: Time.current)
      incident = Incident.open!(subject: app, reason: classified.reason)
      fire_team_event(app.team, "app_down", {
        app_name: app.name,
        reason: classified.reason,
        reason_message: classified.message,
        since: incident.started_at.iso8601
      })
    else
      app.update_columns(uptime_failures: failures, last_uptime_check_at: Time.current)
    end
  end
end

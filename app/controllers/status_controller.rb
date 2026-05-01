class StatusController < ApplicationController
  layout "landing"

  skip_before_action :authenticate_user!, raise: false

  def show
    @web_ok = true # this very response means web is up
    @db_ok  = check_database
    @worker_ok, @worker_lag_seconds = check_worker
    @queue_depth = pending_queue_size
    @recent_incidents = recent_incidents

    @overall = if @db_ok && @worker_ok && @web_ok
                 :operational
    elsif @db_ok && @web_ok
                 :degraded
    else
                 :down
    end
  end

  private

  def check_database
    ActiveRecord::Base.connection.execute("SELECT 1")
    true
  rescue StandardError
    false
  end

  # Healthy worker = at least one job finished within the last 10 minutes.
  # Solid Queue keeps a `solid_queue_jobs` row per processed job; the
  # finished_at timestamp tells us when. If nothing has finished, either
  # the worker is down or the queue is genuinely idle — we can't
  # distinguish without extra signals, so we report "lag" rather than
  # a flat down/up.
  def check_worker
    last = SolidQueue::Job.where.not(finished_at: nil).order(finished_at: :desc).first
    return [ false, nil ] unless last
    lag = (Time.current - last.finished_at).to_i
    [ lag < 600, lag ]
  rescue StandardError
    [ false, nil ]
  end

  def pending_queue_size
    SolidQueue::ReadyExecution.count + SolidQueue::ScheduledExecution.count
  rescue StandardError
    nil
  end

  # Sentry would be the right source long-term. For v1, surface
  # Activity entries we mark with severity:incident so an admin can
  # publish an outage line manually.
  def recent_incidents
    return [] unless defined?(Activity)
    Activity.where("metadata @> ?", { severity: "incident" }.to_json)
            .order(created_at: :desc).limit(5)
  rescue StandardError
    []
  end
end

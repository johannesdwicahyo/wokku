require "net/ssh"
require "digest"

# Reconciles AppRecord#status (what the dashboard shows) against the
# actual container state on the Dokku host, and Sentry-warns on drift.
# v2: it now WRITES the reconciled status for the running<->crashed pair
# (a running record with no container -> :crashed; a crashed record with a
# live container -> :running). It never auto-flips :stopped/:sleeping —
# those are intentional states — and only writes when the host probe
# succeeded (it returns early on an unreachable host, so a transient SSH
# blip can never mass-flip every app to :crashed).
#
# Two failure modes the 2026-05-14 incident exposed:
#
#   1. AppRecord says :running but no container exists. Happens when
#      dockerd dies (live-restore kept records sane historically but
#      cgroups/networking gaps can still drop containers silently) or
#      when a SleepAppsJob ps:stop ran but our status update raced.
#
#   2. AppRecord says :sleeping/:stopped/:crashed but a container is
#      live. Happens when a user manually `dokku ps:start`-ed via SSH
#      bypassing the dashboard, or when our state writes lost a
#      transaction.
#
# Either way, the dashboard lies. Sentry warns within ~10 minutes — but
# debounced per unique drift signature (see #report_drift) so a persistent
# drift doesn't re-fire on every poll.
class ReconcileAppStatusesJob < ApplicationJob
  queue_as :health

  # Containers we ignore — they're not user apps.
  IGNORED_CONTAINERS = %w[dokku dokku-shared-postgres dokku-shared-mariadb prom01 nginx-proxy].freeze

  def perform(server_id)
    server = Server.find_by(id: server_id)
    return unless server
    return if server.ssh_private_key.blank?

    running_names = fetch_running_app_names(server)
    return if running_names.nil? # SSH unreachable — separate alert path

    discrepancies = []

    # Skip Swarm-lifecycle apps: their containers are named
    # `wokku-<app>-<proc>.<slot>.<taskid>`, which the dokku-derived
    # `split(".").first` scan never matches — and their dokku container is
    # intentionally stopped post-adopt — so every adopted app would false-flip
    # to :crashed on the next cycle. Their status truth is live_containers.
    server.app_records.where(wokkud_lifecycle: false).find_each do |app|
      live = running_names.include?(app.name)
      status = app.status.to_s

      # v2: write the reconciled status (only the running<->crashed pair;
      # :stopped/:sleeping are intentional states we never auto-flip).
      if status == "running" && !live
        app.update!(status: :crashed)
        discrepancies << "AppRecord #{app.id} (#{app.name}) status=running but no container on host -> :crashed"
      elsif status == "crashed" && live
        app.update!(status: :running)
        discrepancies << "AppRecord #{app.id} (#{app.name}) status=crashed but container IS running on host -> :running"
      elsif %w[sleeping stopped].include?(status) && live
        discrepancies << "AppRecord #{app.id} (#{app.name}) status=#{status} but container IS running on host"
      end
    end

    # Flagged apps (B6 W4): status truth is the Swarm task state the
    # heartbeat fans out to app_records.live_containers — nothing else
    # writes their status post-adoption, so a crash-looping task showed
    # :running forever. Same running<->crashed pair only; a stale heartbeat
    # (agent down) means we don't guess.
    server.app_records.where(wokkud_lifecycle: true).find_each do |app|
      next if app.live_containers_at.nil? || app.live_containers_at < 10.minutes.ago
      web_running = Array(app.live_containers).any? { |c| c["process"] == "web" && c["state"] == "running" }
      status = app.status.to_s

      if status == "running" && !web_running
        app.update!(status: :crashed)
        discrepancies << "AppRecord #{app.id} (#{app.name}) status=running but no running web task -> :crashed"
      elsif status == "crashed" && web_running
        app.update!(status: :running)
        discrepancies << "AppRecord #{app.id} (#{app.name}) status=crashed but web task IS running -> :running"
      end
    end

    report_drift(server, discrepancies) if discrepancies.any?
  rescue StandardError => e
    Rails.logger.warn("ReconcileAppStatusesJob: #{server_id}: #{e.class}: #{e.message}")
    Sentry.capture_exception(e, level: :warning, extra: { server_id: server_id }) if defined?(Sentry)
  end

  private

  # Sentry-warn at most once per unique drift signature per server (6h TTL).
  # Without this, a persistent drift — e.g. the warn-only case where an
  # intentionally :stopped/:sleeping app still has a live container, which we
  # surface but deliberately never auto-flip — fires on every 10-min poll and
  # floods Sentry (it was 35% of all events). A changed drift set produces a
  # new signature and warns again; a stable one re-warns at most every 6h.
  def report_drift(server, discrepancies)
    summary = "ReconcileAppStatusesJob: #{discrepancies.size} drift(s) on #{server.name}"
    Rails.logger.warn(summary)

    signature = Digest::MD5.hexdigest(discrepancies.sort.join("|"))
    key = "reconcile:warned:#{server.id}:#{signature}"
    return if Rails.cache.read(key)

    Rails.cache.write(key, true, expires_in: 6.hours)
    discrepancies.first(10).each { |d| Rails.logger.warn("  - #{d}") }
    return unless defined?(Sentry)

    Sentry.capture_message(summary, level: :warning, extra: {
      server_id: server.id,
      server_name: server.name,
      discrepancies: discrepancies.first(30)
    })
  end

  # Returns Set<String> of app names with a running container on the
  # host, or nil if SSH/Docker is unreachable (so the caller can skip
  # rather than mistake "can't reach" for "every app is missing").
  def fetch_running_app_names(server)
    output = Net::SSH.start(server.host, Hosts::Ssh.user,
                            port: server.port || 22,
                            non_interactive: true,
                            timeout: 5,
                            key_data: Array(server.ssh_private_key).reject(&:blank?)) do |ssh|
      ssh.exec!('docker ps --format "{{.Names}}" 2>&1').to_s
    end

    if output.include?("Cannot connect to the Docker daemon")
      Rails.logger.warn("ReconcileAppStatusesJob: docker daemon down on #{server.name}, skipping")
      return nil
    end

    # Container names look like <app>.<process>.<instance> (e.g.
    # batumas.web.1) or <app>.web.1.upcoming-... for in-flight deploys.
    # Strip everything after the first dot to get the app name.
    output.lines.map { |l| l.strip.split(".").first }
          .reject { |n| n.blank? || IGNORED_CONTAINERS.include?(n) || n.start_with?("dokku.") }
          .uniq
          .to_set
  rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT, Errno::EHOSTUNREACH,
         Errno::ENETUNREACH, SocketError, Net::SSH::Exception
    nil
  end
end

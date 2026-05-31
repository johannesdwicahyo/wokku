require "net/ssh"

# Read-only audit: compares AppRecord#status (what the dashboard shows)
# against the actual container state on the Dokku host. Surfaces drift
# via Sentry without mutating anything — v1 is observe-only so we can
# trust the signal before adding auto-remediation.
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
# Either way, the dashboard lies. Sentry warns within ~10 minutes.
class ReconcileAppStatusesJob < ApplicationJob
  queue_as :health

  # Containers we ignore — they're not user apps.
  IGNORED_CONTAINERS = %w[dokku dokku-shared-postgres prom01 nginx-proxy].freeze

  def perform(server_id)
    server = Server.find_by(id: server_id)
    return unless server
    return if server.ssh_private_key.blank?

    running_names = fetch_running_app_names(server)
    return if running_names.nil? # SSH unreachable — separate alert path

    discrepancies = []

    server.app_records.find_each do |app|
      live = running_names.include?(app.name)
      status = app.status.to_s

      if status == "running" && !live
        discrepancies << "AppRecord #{app.id} (#{app.name}) status=running but no container on host"
      elsif %w[sleeping stopped crashed].include?(status) && live
        discrepancies << "AppRecord #{app.id} (#{app.name}) status=#{status} but container IS running on host"
      end
    end

    if discrepancies.any?
      summary = "ReconcileAppStatusesJob: #{discrepancies.size} drift(s) on #{server.name}"
      Rails.logger.warn(summary)
      discrepancies.first(10).each { |d| Rails.logger.warn("  - #{d}") }
      if defined?(Sentry)
        Sentry.capture_message(summary, level: :warning, extra: {
          server_id: server.id,
          server_name: server.name,
          discrepancies: discrepancies.first(30)
        })
      end
    end
  rescue StandardError => e
    Rails.logger.warn("ReconcileAppStatusesJob: #{server_id}: #{e.class}: #{e.message}")
    Sentry.capture_exception(e, level: :warning, extra: { server_id: server_id }) if defined?(Sentry)
  end

  private

  # Returns Set<String> of app names with a running container on the
  # host, or nil if SSH/Docker is unreachable (so the caller can skip
  # rather than mistake "can't reach" for "every app is missing").
  def fetch_running_app_names(server)
    output = Net::SSH.start(server.host, "root",
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

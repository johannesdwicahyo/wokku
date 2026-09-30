require "net/ssh"

# Probes `systemctl is-active docker` on a single Dokku host and records
# the result on Server#docker_status. Distinguishes "dockerd is dead"
# from "dokku CLI broken" or "host unreachable" — when the regular
# HealthCheckJob fails, we want to know which layer it is.
#
# On non-"active" status, Sentry-warns so we get an alert within ~5
# minutes (the scheduler cadence) of dockerd dying. The 2026-05-14
# incident sat with dockerd in `failed` state for hours before we
# discovered it by accident; this job closes that gap.
class DockerHealthCheckJob < ApplicationJob
  queue_as :health

  def perform(server_id)
    server = Server.find_by(id: server_id)
    return unless server
    return if server.ssh_private_key.blank?

    status = probe_docker(server)
    previous_status = server.docker_status

    server.update_columns(
      docker_status: status,
      docker_status_checked_at: Time.current
    )

    if status != "active" && defined?(Sentry)
      # Only page on transition to non-active, not on every poll while
      # it's down. Subsequent pings happen via the scheduler cadence.
      if previous_status != status
        Sentry.capture_message(
          "Docker daemon non-active on #{server.name} (#{server.host}): status=#{status}",
          level: :error,
          extra: { server_id: server.id, host: server.host, status: status, previous_status: previous_status }
        )
      end
    end
  rescue StandardError => e
    Rails.logger.warn("DockerHealthCheckJob: probe failed for server #{server_id}: #{e.class}: #{e.message}")
    Sentry.capture_exception(e, level: :warning, extra: { server_id: server_id }) if defined?(Sentry)
  end

  private

  # Returns one of: "active", "failed", "inactive", "activating",
  # "deactivating", or "unreachable" (we couldn't SSH at all).
  def probe_docker(server)
    Net::SSH.start(server.host, Hosts::Ssh.user,
                   port: server.port || 22,
                   non_interactive: true,
                   timeout: 5,
                   key_data: Array(server.ssh_private_key).reject(&:blank?)) do |ssh|
      out = ssh.exec!("#{docker_health_command} 2>&1").to_s.strip
      # is-active returns a single token on stdout; trim anything spurious.
      out.split("\n").last.to_s.strip.presence || "unknown"
    end
  rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT, Errno::EHOSTUNREACH,
         Errno::ENETUNREACH, SocketError, Net::SSH::Exception => _
    "unreachable"
  end

  # systemctl needs root; a non-root host user goes through the helper
  # (same `active`/`failed`/... output).
  def docker_health_command
    Hosts::Ssh.root_user? ? "systemctl is-active docker" : "sudo -n /usr/local/sbin/wokku-docker-health"
  end
end

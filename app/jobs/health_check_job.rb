# Keeps the legacy Server#status enum (connected/unreachable) in sync with
# reality. W7 Phase 2: reachability truth is wokkud heartbeat freshness —
# no SSH probe. The down-transition paging (Incident + OpsMailer) is owned
# by HostHeartbeatMonitorJob; this job only maintains the status column the
# dashboard/API still read, plus its own Sentry transition alert.
class HealthCheckJob < ApplicationJob
  queue_as :health

  def perform(server_id)
    server = Server.find(server_id)

    if server.heartbeat_stale?
      mark_unreachable(server)
    else
      server.update_column(:status, Server.statuses[:connected])
    end
  end

  private

  # Flip status to unreachable and page the operator — but only on the
  # transition (was-not-unreachable → unreachable), not on every poll
  # while the host stays down. Mirrors DockerHealthCheckJob's alerting.
  def mark_unreachable(server)
    was_unreachable = server.unreachable?
    server.update_column(:status, Server.statuses[:unreachable])

    return unless defined?(Sentry)
    return if was_unreachable

    Sentry.capture_message(
      "Dokku host unreachable: #{server.name} (#{server.host})",
      level: :error,
      extra: { server_id: server.id, host: server.host }
    )
  end
end

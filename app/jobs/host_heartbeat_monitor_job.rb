# The other half of the wokkud heartbeat: the agent can't tell us it
# died, so the absence of beats is the down signal. Runs every minute;
# with 15s beats and a 60s staleness window, a dead host is paged
# within ~60–120s. Recovery is detected by Server#record_heartbeat!
# (the next beat), not here.
class HostHeartbeatMonitorJob < ApplicationJob
  queue_as :health

  def perform
    Server.where.not(agent_version: nil).find_each do |server|
      next unless server.heartbeat_stale?
      next if server.heartbeat_status == "down" # already paged this outage

      server.update_columns(heartbeat_status: "down")
      Incident.open!(subject: server, reason: "host_down", started_at: server.heartbeat_at || Time.current)
      OpsMailer.host_down(server).deliver_later

      if defined?(Sentry)
        Sentry.capture_message(
          "Host heartbeat lost: #{server.name} (#{server.host}) — last beat #{server.heartbeat_at&.iso8601 || 'never'}",
          level: :error,
          extra: { server_id: server.id, host: server.host, vitals: server.vitals }
        )
      end
    end
  end
end

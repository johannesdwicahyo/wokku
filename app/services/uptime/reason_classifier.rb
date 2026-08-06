# frozen_string_literal: true

module Uptime
  # Layered down-reason attribution (Track A Phase 5), first match wins:
  # our-host problems before app problems before raw probe kinds — so the
  # owner notification can say "not your code" when it's ours. Single home
  # for the owner-facing copy, mirroring Hosts::ErrorClassifier's role for
  # command errors.
  class ReasonClassifier
    RECENT_CRASH_WINDOW = 5.minutes

    Result = Struct.new(:reason, :message, keyword_init: true)

    PROBE_MESSAGES = {
      http_5xx: "the app is responding with server errors (HTTP 5xx) — check `wokku logs`",
      timeout: "the app is not answering within 10s",
      ssl_error: "the app's SSL certificate is failing the handshake",
      dns_error: "the app's domain is not resolving",
      connection_refused: "nothing is listening on the app's port"
    }.freeze

    def self.call(app, failure_kind)
      server = app.server
      if server.agent_installed? && server.heartbeat_stale?
        return Result.new(reason: "host_down",
          message: "host #{server.name} is unreachable — not your code, our host is down and we are on it")
      end
      if app.stopped? || app.sleeping?
        return Result.new(reason: "app_stopped", message: "the app is stopped")
      end
      if app.crashed? || app.crash_events.where("exited_at > ?", RECENT_CRASH_WINDOW.ago).exists?
        return Result.new(reason: "app_crashed",
          message: "the app's container crashed — check `wokku logs` for the crash output")
      end
      Result.new(reason: failure_kind.to_s,
        message: PROBE_MESSAGES.fetch(failure_kind, "the app is not responding"))
    end
  end
end

class SyncServerJob < ApplicationJob
  queue_as :sync

  # B6 quiescence, collapsed in W7 Phase 1: every record class this job once
  # reconciled against dokku (apps, domains, databases, links) is
  # control-plane-owned on a fully-wokkud server — dokku's lists were dead
  # metadata (the 2026-07-18 domain wipe was this job) and dokku leaves the
  # host at W8. The scheduled sweep now just confirms the server as connected.
  def perform(server_id)
    server = Server.find(server_id)
    server.update_column(:status, Server.statuses[:connected])
  end
end

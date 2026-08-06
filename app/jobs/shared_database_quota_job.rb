# frozen_string_literal: true

# Periodic per-server sweep: delegates the actual size measurement +
# revoke/restore work to wokkud via a typed service.check_quotas op on the
# shared-postgres parent, then mirrors the over-quota state into Rails for
# billing/notification purposes.
#
# Failure of one server's op does NOT kill the sweep — we log and continue.
# wokkud handles all SQL on the host; Rails owns `over_quota_at` and (if
# wired) the team-event notifications.
class SharedDatabaseQuotaJob < ApplicationJob
  include Notifiable
  queue_as :default

  def perform
    Server.find_each do |server|
      pg_tenants = DatabaseService.where(server: server, shared: true, service_type: "postgres")
      pg_parent  = pg_tenants.first&.parent_service
      next unless pg_parent

      sweep_pg_via_ops!(pg_tenants, pg_parent)
    end
  end

  private

  # Phase B4: the shared-postgres parent is wokkud-managed. CARRY-FORWARD:
  # this op is shared-postgres-only (wokkud has no equivalent for other
  # shared engines yet), so only this engine's tenants get swept.
  def sweep_pg_via_ops!(tenants, parent)
    op = Services::Ops.issue_and_wait!(
      service: parent, kind: "service.check_quotas",
      params: { tenants: tenants.map { |t| { slug: t.shared_db_name, cap_bytes: t.storage_mb_quota.to_i * 1.megabyte } } }
    )

    statuses = (op.result["tenants"] || []).index_by { |s| s["slug"] }
    tenants.each do |tenant|
      status = statuses[tenant.shared_db_name]
      next unless status

      if status["over"] && tenant.over_quota_at.nil?
        tenant.update!(over_quota_at: Time.current)
        fire_team_event(team_for(tenant), "shared_db_over_quota", db: tenant.name, size_mb: status["size_bytes"].to_i / 1.megabyte)
      elsif !status["over"] && tenant.over_quota_at.present?
        tenant.update!(over_quota_at: nil)
      end
    end
  rescue Services::Ops::Failed, Services::Ops::Timeout => e
    Rails.logger.warn("SharedDatabaseQuotaJob: #{parent.server.host} — #{e.class}: #{e.message}")
  end

  def team_for(tenant)
    tenant.app_records.first&.team
  end
end

# frozen_string_literal: true

# Periodic per-server sweep: delegates the actual size measurement +
# revoke/restore work to wokkud via a typed service.check_quotas op on each
# shared parent (postgres, mariadb, redis), then mirrors the over-quota state
# into Rails for billing/notification purposes.
#
# Failure of one server's op does NOT kill the sweep — we log and continue.
# wokkud handles all SQL on the host; Rails owns `over_quota_at` and (if
# wired) the team-event notifications.
class SharedDatabaseQuotaJob < ApplicationJob
  include Notifiable
  queue_as :default

  def perform
    Server.find_each do |server|
      DatabaseService::SHARED_ENGINES.each do |engine|
        tenants = DatabaseService.where(server: server, shared: true, service_type: engine)
        parent  = tenants.first&.parent_service
        next unless parent

        sweep_via_ops!(tenants, parent)
      end
    end
  end

  private

  # Same op + semantics for every engine: wokkud measures each tenant and
  # flips it read-only (postgres) / write-revoked (mariadb, redis) when over
  # its cap. SQL tenants carry storage_mb_quota (stamped at provision);
  # redis tenants don't, so their cap comes from the creator's plan.
  def sweep_via_ops!(tenants, parent)
    op = Services::Ops.issue_and_wait!(
      service: parent, kind: "service.check_quotas",
      params: { tenants: tenants.map { |t| { slug: slug(t), cap_bytes: cap_mb(t) * 1.megabyte } } }
    )

    statuses = (op.result["tenants"] || []).index_by { |s| s["slug"] }
    tenants.each do |tenant|
      status = statuses[slug(tenant)]
      next unless status
      # wokkud reports a per-tenant failure instead of aborting the sweep
      # (mariadb); its over/size fields are meaningless — change nothing.
      if status["error"].present?
        Rails.logger.warn("SharedDatabaseQuotaJob: #{tenant.name} check failed: #{status['error']}")
        next
      end

      # MetricsPollJob skips shared rows, so this sweep is their only size
      # source (the over-quota banner + dedicated-upgrade cap check read it).
      tenant.update_columns(live_db_bytes: status["size_bytes"].to_i, live_metrics_at: Time.current)

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

  # Plugin-era rows lack shared_db_name; a blank slug makes wokkud reject the
  # whole sweep (2026-10-06: superscalper's row stalled every redis tenant).
  def slug(tenant)
    DatabaseProvisioner.shared_tenant_slug(tenant)
  end

  # ponytail: no plan → 10 MB (the shared_redis_mb_per_tenant column default)
  # rather than 0, which would flip every planless tenant read-only.
  def cap_mb(tenant)
    tenant.storage_mb_quota || tenant.creator&.current_plan&.shared_tenant_cap(tenant.service_type) || 10
  end

  def team_for(tenant)
    tenant.app_records.first&.team
  end
end

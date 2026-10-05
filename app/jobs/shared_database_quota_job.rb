# frozen_string_literal: true

# Periodic per-server sweep: delegates the actual size measurement +
# revoke/restore work to wokkud via a typed service.check_quotas op on each
# shared SQL parent (postgres, mariadb), then mirrors the over-quota state into Rails for
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
      DatabaseProvisioner::SHARED_PARENTS.each_key do |engine|
        tenants = DatabaseService.where(server: server, shared: true, service_type: engine)
        parent  = tenants.first&.parent_service
        next unless parent

        sweep_via_ops!(tenants, parent)
      end
    end
  end

  private

  # Same op + semantics for both SQL engines: wokkud measures each tenant
  # and flips it read-only (postgres) / write-revoked (mariadb) when over
  # its storage_mb_quota (stamped from plan.db_bundle_mb at provision).
  # Redis/memcached tenants are not swept here.
  def sweep_via_ops!(tenants, parent)
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

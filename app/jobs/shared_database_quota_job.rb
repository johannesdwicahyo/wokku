# Enforces per-tenant storage quotas on shared Postgres clusters.
# Runs every 30 min. For each server that hosts a shared cluster, queries
# pg_database_size for all tenant DBs and flips over_quota when they exceed
# their storage_mb_quota. On flip:
#   - first transition: set over_quota_at (grace period begins)
#   - if over_quota for > 24h: revoke INSERT/UPDATE/DELETE (reads still allowed)
#   - once back under quota: clear over_quota_at + restore writes
class SharedDatabaseQuotaJob < ApplicationJob
  queue_as :default

  GRACE_PERIOD = 24.hours

  def perform
    Server.where(status: [ Server.statuses[:connected], Server.statuses[:syncing] ]).find_each do |server|
      enforce_for_server(server)
    end
  end

  private

  def enforce_for_server(server)
    shared_tenants = server.database_services.shared_tenants.where(service_type: "postgres")
    return if shared_tenants.empty?

    client = Dokku::Client.new(server)
    shared = Dokku::SharedPostgres.new(client)
    sizes = shared.database_sizes

    shared_tenants.find_each do |tenant|
      next if tenant.storage_mb_quota.blank? || tenant.shared_db_name.blank?
      bytes = sizes[tenant.shared_db_name].to_i
      quota_bytes = tenant.storage_mb_quota * 1_024 * 1_024

      if bytes > quota_bytes
        handle_over_quota(tenant, shared)
      elsif tenant.over_quota?
        handle_back_under(tenant, shared)
      end
    end
  rescue => e
    Rails.logger.warn "SharedDatabaseQuotaJob: server #{server.name} failed: #{e.message}"
  end

  def handle_over_quota(tenant, shared)
    if tenant.over_quota_at.blank?
      tenant.update!(over_quota_at: Time.current)
      Rails.logger.info "Shared DB #{tenant.shared_db_name} over quota — grace period begins"
    elsif tenant.over_quota_at < GRACE_PERIOD.ago && tenant.status != "stopped"
      shared.revoke_writes!(role_name: tenant.shared_role_name, db_name: tenant.shared_db_name)
      tenant.update!(status: :stopped)
      Rails.logger.warn "Shared DB #{tenant.shared_db_name} writes revoked — grace period expired"
    end
  end

  def handle_back_under(tenant, shared)
    tenant.update!(over_quota_at: nil)
    if tenant.status == "stopped"
      shared.restore_writes!(role_name: tenant.shared_role_name, db_name: tenant.shared_db_name)
      tenant.update!(status: :running)
      Rails.logger.info "Shared DB #{tenant.shared_db_name} writes restored"
    end
  end
end

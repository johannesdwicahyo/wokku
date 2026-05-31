# frozen_string_literal: true

# Periodic per-server sweep: delegates the actual size measurement +
# revoke/restore work to the dokku-shared-postgres plugin via
# `shared-postgres:check-quotas`, then mirrors the plugin's
# over-quota state into Rails for billing/notification purposes.
#
# Failure of one server's plugin call does NOT kill the sweep — we log
# and continue. The plugin handles all SQL on the host; Rails owns
# `over_quota_at` and (if wired) the team-event notifications.
class SharedDatabaseQuotaJob < ApplicationJob
  include Notifiable
  queue_as :default

  def perform
    Server.find_each do |server|
      next unless DatabaseService.exists?(server: server, shared: true)

      reports = fetch_reports(server)
      apply_reports(server, reports)
    end
  end

  private

  def fetch_reports(server)
    client = Dokku::Client.new(server)
    Dokku::SharedPostgres.new(client).check_quotas!
  rescue Dokku::Client::CommandError, Dokku::Client::ConnectionError => e
    Rails.logger.warn("SharedDatabaseQuotaJob: #{server.host} — #{e.class}: #{e.message}")
    []
  end

  def apply_reports(server, reports)
    reports.each do |r|
      tenant = DatabaseService.find_by(server: server, name: r[:name], shared: true)
      next unless tenant

      if r[:over_quota] && tenant.over_quota_at.nil?
        tenant.update!(over_quota_at: Time.current)
        fire_team_event(team_for(tenant), "shared_db_over_quota", db: tenant.name, size_mb: r[:size_mb])
      elsif !r[:over_quota] && tenant.over_quota_at.present?
        tenant.update!(over_quota_at: nil)
      end
    end
  end

  def team_for(tenant)
    tenant.app_records.first&.team
  end
end

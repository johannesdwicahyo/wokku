module Molecules
  class BackupsSummaryCardComponent < ApplicationComponent
    def initialize(app:, current_user:, can_update: true)
      @app = app
      @can_update = can_update
      @user = current_user
      @last_backup = app.respond_to?(:last_backup) ? app.last_backup : nil
      @has_database = app.respond_to?(:primary_database) && app.primary_database.present?
    end
    attr_reader :app, :user, :last_backup, :has_database

    def can_update? = @can_update

    # Describes the DB's actual GFS keep-set (per-tier, see
    # ServiceTier::BACKUP_POLICIES) — e.g. "Daily · keeps 7 daily + 4 weekly
    # + 1 monthly". "On-demand only" when there's no DB or its tier has no
    # scheduled backups (shared_free).
    def policy_label
      db = has_database ? app.primary_database : nil
      policy = db.respond_to?(:backup_policy) ? db.backup_policy : nil
      return t("apps.backups.on_demand") unless policy&.dig(:auto_backup)

      kept = policy[:gfs].to_h.filter_map { |unit, n| t("apps.backups.unit.#{unit}", count: n.to_i) if n.to_i.positive? }
      t("apps.backups.keeps", parts: kept.join(" + "))
    end
  end
end

module Molecules
  class BackupsSummaryCardComponent < ApplicationComponent
    def initialize(app:, current_user:)
      @app = app
      @user = current_user
      @last_backup = app.respond_to?(:last_backup) ? app.last_backup : nil
      @has_database = app.respond_to?(:primary_database) && app.primary_database.present?
    end
    attr_reader :app, :user, :last_backup, :has_database

    # Describes the DB's actual GFS keep-set (per-tier, see
    # ServiceTier::BACKUP_POLICIES) — e.g. "Daily · keeps 7 daily + 4 weekly
    # + 1 monthly". "On-demand only" when there's no DB or its tier has no
    # scheduled backups (shared_free).
    def policy_label
      db = has_database ? app.primary_database : nil
      policy = db.respond_to?(:backup_policy) ? db.backup_policy : nil
      return "On-demand only" unless policy&.dig(:auto_backup)

      kept = policy[:gfs].to_h.filter_map { |unit, n| "#{n} #{unit}" if n.to_i.positive? }
      "Daily · keeps #{kept.join(' + ')}"
    end
  end
end

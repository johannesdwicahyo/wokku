module Molecules
  class BackupsSummaryCardComponent < ApplicationComponent
    def initialize(app:, current_user:)
      @app = app
      @user = current_user
      @last_backup = app.respond_to?(:last_backup) ? app.last_backup : nil
      @retention_days = current_user&.plan&.backup_retention_days.to_i
      @has_database = app.respond_to?(:primary_database) && app.primary_database.present?
    end
    attr_reader :app, :user, :last_backup, :retention_days, :has_database

    # "On-demand only" when the plan has zero retention (Free), else
    # "Daily · N-day retention". Reads from Plan#backup_retention_days
    # which is a NOT NULL column (0 = no scheduled backups).
    def policy_label
      retention_days.positive? ? "Daily · #{retention_days}-day retention" : "On-demand only"
    end
  end
end

class MakeServerTeamNullable < ActiveRecord::Migration[8.1]
  # Platform-level servers are added by a system admin and accessible to all
  # users. We keep the team_id column for backfill/audit, but it's no longer
  # required — servers stand on their own as platform infrastructure.
  def change
    change_column_null :servers, :team_id, true
  end
end

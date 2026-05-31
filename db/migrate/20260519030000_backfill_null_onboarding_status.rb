class BackfillNullOnboardingStatus < ActiveRecord::Migration[8.1]
  def up
    # Defensive: any row that escaped the 20260518030000 backfill
    # (legacy/dev rows inserted around the add_column) must not be NULL.
    # 2 == completed (do not retro-show the tour to pre-existing users).
    execute "UPDATE users SET onboarding_status = 2 WHERE onboarding_status IS NULL"
  end

  def down
    # no-op (cannot distinguish backfilled rows)
  end
end

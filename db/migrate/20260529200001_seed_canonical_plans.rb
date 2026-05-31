class SeedCanonicalPlans < ActiveRecord::Migration[8.1]
  # Phase 4 cutover follow-up. After `AddNewColumnsToPlans` backfills the
  # `key` column on existing rows, the price / bundle / retention columns
  # are still at their schema defaults (0, "manual", etc.) on production.
  # Load db/seeds/plans.rb to upsert the canonical four-plan layout —
  # find_or_initialize_by(key:) means existing rows get updated in place
  # so foreign-key references from subscriptions / teams / invoices stay
  # intact.
  #
  # Runs near the END of the migration chain so every column added by
  # intervening migrations (box_quotas, bundle columns, retention columns,
  # extra_seat_idr, etc.) already exists by the time the seed runs.
  def up
    load Rails.root.join("db/seeds/plans.rb")
  end

  def down
    # No-op — we'd never want to delete prod plan rows in a rollback.
  end
end

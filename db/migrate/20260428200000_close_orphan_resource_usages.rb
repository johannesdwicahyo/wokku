class CloseOrphanResourceUsages < ActiveRecord::Migration[8.1]
  # One-shot data migration. Runs the orphan-segment closer on deploy
  # so the production "Running resources" table stops showing rows for
  # apps and databases that don't exist anymore.
  #
  # Safe under the new code path because:
  #   - the legacy `AppRecord:<id>` segments stopped being created when
  #     deploy_job and friends dropped their track_resource_usage! calls
  #     (this branch); closing the existing ones here puts them in the
  #     same state as if the (never-attached) close callback had run.
  #   - dyno-allocation segments whose AppRecord no longer exists were
  #     never billable beyond the deletion timestamp anyway — closing
  #     "now" only affects the live table, since cost_cents_in_period
  #     ignores hours past stopped_at.
  def up
    return unless defined?(Billing::CloseOrphanSegments)
    stats = Billing::CloseOrphanSegments.call
    say "CloseOrphanSegments: #{stats.inspect}"
  end

  def down
    # Cannot reopen a frozen segment safely — the started_at is preserved
    # but cost_cents_in_period would resume billing at today's clock for
    # an app that no longer exists. Intentionally a no-op.
  end
end

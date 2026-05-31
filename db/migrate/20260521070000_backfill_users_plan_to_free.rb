class BackfillUsersPlanToFree < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    free_plan_id = execute("SELECT id FROM plans WHERE key = 'free' LIMIT 1").first&.fetch("id")
    raise "Plan(key=free) must be seeded before backfill" unless free_plan_id

    User.in_batches(of: 500) do |batch|
      batch.where(plan_id: nil).update_all(plan_id: free_plan_id)
    end
  end

  def down
    User.in_batches(of: 500) do |batch|
      batch.update_all(plan_id: nil)
    end
  end
end

class AddPendingPlanToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :pending_plan_id, :uuid
    add_column :users, :plan_changes_at, :datetime
  end
end

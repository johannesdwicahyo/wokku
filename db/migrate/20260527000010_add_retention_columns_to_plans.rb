class AddRetentionColumnsToPlans < ActiveRecord::Migration[8.1]
  def change
    # Retention windows from the bundles spec (project_plan_bundles_box_rename_spec).
    # Defaults below align with the Free tier so accidentally-Free apps keep
    # the cheapest cohort.
    add_column :plans, :log_retention_days,              :integer, null: false, default: 1
    add_column :plans, :sample_retention_hours,          :integer, null: false, default: 24
    add_column :plans, :metric_high_res_days,            :integer, null: false, default: 1
    add_column :plans, :metric_aggregate_retention_days, :integer, null: false, default: 7
  end
end

class AddDefaultsToLegacyPlanColumns < ActiveRecord::Migration[8.1]
  def change
    change_column_default :plans, :max_apps,               from: nil, to: 0
    change_column_default :plans, :max_dynos,              from: nil, to: 0
    change_column_default :plans, :max_databases,          from: nil, to: 0
    change_column_default :plans, :price_cents_per_month,  from: nil, to: 0
  end
end

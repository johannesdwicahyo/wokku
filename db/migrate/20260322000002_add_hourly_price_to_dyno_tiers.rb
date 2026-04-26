class AddHourlyPriceToDynoTiers < ActiveRecord::Migration[8.1]
  def change
    add_column :dyno_tiers, :price_cents_per_hour, :decimal, precision: 10, scale: 4, default: 0, null: false
    change_column_null :dyno_tiers, :price_cents_per_month, true
  end
end

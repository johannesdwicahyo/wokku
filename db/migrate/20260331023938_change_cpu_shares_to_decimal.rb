class ChangeCpuSharesToDecimal < ActiveRecord::Migration[8.1]
  def up
    change_column :dyno_tiers, :cpu_shares, :decimal, precision: 4, scale: 2, default: 0, null: false

    execute <<~SQL
      UPDATE dyno_tiers SET cpu_shares = CASE name
        WHEN 'eco' THEN 0.25
        WHEN 'basic' THEN 0.5
        WHEN 'standard-1x' THEN 0.75
        WHEN 'standard-2x' THEN 1.5
        WHEN 'performance' THEN 2.0
        ELSE cpu_shares / 100.0
      END
    SQL
  end

  def down
    execute <<~SQL
      UPDATE dyno_tiers SET cpu_shares = CASE name
        WHEN 'eco' THEN 25
        WHEN 'basic' THEN 50
        WHEN 'standard-1x' THEN 100
        WHEN 'standard-2x' THEN 200
        WHEN 'performance' THEN 400
        ELSE cpu_shares * 100
      END
    SQL
    change_column :dyno_tiers, :cpu_shares, :integer, default: 0, null: false
  end
end

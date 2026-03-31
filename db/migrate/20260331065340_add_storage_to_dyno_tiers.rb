class AddStorageToDynoTiers < ActiveRecord::Migration[8.1]
  def change
    add_column :dyno_tiers, :storage_mb, :integer, default: 0, null: false
    add_column :dyno_tiers, :max_per_user, :integer

    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE dyno_tiers SET storage_mb = CASE name
            WHEN 'free' THEN 0
            WHEN 'basic' THEN 512
            WHEN 'standard' THEN 1024
            WHEN 'performance' THEN 2048
            WHEN 'performance-2x' THEN 5120
            ELSE 0
          END,
          max_per_user = CASE name
            WHEN 'free' THEN 1
            ELSE NULL
          END
        SQL
      end
    end
  end
end

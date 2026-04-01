class AddScalableToDynoTiers < ActiveRecord::Migration[8.1]
  def change
    add_column :dyno_tiers, :scalable, :boolean, default: false, null: false

    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE dyno_tiers SET scalable = CASE
            WHEN name IN ('standard', 'performance', 'performance-2x') THEN true
            ELSE false
          END
        SQL
      end
    end
  end
end

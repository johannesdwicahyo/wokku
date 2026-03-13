class CreateDynoTiers < ActiveRecord::Migration[8.1]
  def change
    create_table :dyno_tiers do |t|
      t.string :name, null: false
      t.integer :memory_mb, null: false
      t.integer :cpu_shares, null: false
      t.integer :price_cents_per_month, null: false
      t.boolean :sleeps, null: false, default: false

      t.timestamps
    end

    add_index :dyno_tiers, :name, unique: true
  end
end

class CreateDynoAllocations < ActiveRecord::Migration[8.1]
  def change
    create_table :dyno_allocations do |t|
      t.references :app_record, null: false, foreign_key: true
      t.references :dyno_tier, null: false, foreign_key: true
      t.string :process_type, null: false
      t.integer :count, null: false, default: 1

      t.timestamps
    end

    add_index :dyno_allocations, [:app_record_id, :process_type], unique: true
  end
end

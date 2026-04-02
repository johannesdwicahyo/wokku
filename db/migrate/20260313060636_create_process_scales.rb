class CreateProcessScales < ActiveRecord::Migration[8.1]
  def change
    create_table :process_scales do |t|
      t.references :app_record, null: false, foreign_key: true
      t.string :process_type
      t.integer :count, default: 1

      t.timestamps
    end

    add_index :process_scales, [ :app_record_id, :process_type ], unique: true
  end
end

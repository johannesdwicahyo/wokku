class CreateMetrics < ActiveRecord::Migration[8.1]
  def change
    create_table :metrics do |t|
      t.references :app_record, null: false, foreign_key: true
      t.float :cpu_percent
      t.bigint :memory_usage
      t.bigint :memory_limit
      t.datetime :recorded_at

      t.timestamps
    end

    add_index :metrics, [:app_record_id, :recorded_at]
  end
end

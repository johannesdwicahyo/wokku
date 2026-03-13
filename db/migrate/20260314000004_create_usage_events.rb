class CreateUsageEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :usage_events do |t|
      t.references :user, null: false, foreign_key: true
      t.references :app_record, foreign_key: true
      t.string :event_type
      t.json :metadata

      t.timestamps
    end

    add_index :usage_events, [:user_id, :created_at]
  end
end

class CreateActivities < ActiveRecord::Migration[8.1]
  def change
    create_table :activities do |t|
      t.references :user, null: false, foreign_key: true
      t.references :team, null: false, foreign_key: true
      t.string :action, null: false          # "app.created", "app.deployed", "config.updated", etc.
      t.string :target_type                  # "AppRecord", "DatabaseService", "Server", etc.
      t.bigint :target_id
      t.string :target_name                  # Human-readable name (e.g. "my-app")
      t.jsonb :metadata, default: {}         # Additional context
      t.datetime :created_at, null: false
    end
    add_index :activities, [:team_id, :created_at]
    add_index :activities, [:target_type, :target_id]
  end
end

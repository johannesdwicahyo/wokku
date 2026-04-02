class CreateAppRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :app_records do |t|
      t.string :name, null: false
      t.references :server, null: false, foreign_key: true
      t.references :team, null: false, foreign_key: true
      t.integer :status, default: 0
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.string :deploy_branch, default: "main"
      t.datetime :synced_at

      t.timestamps
    end

    add_index :app_records, [ :name, :server_id ], unique: true
  end
end

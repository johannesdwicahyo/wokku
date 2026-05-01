class AddSharedToDatabaseServices < ActiveRecord::Migration[8.1]
  def change
    change_table :database_services, bulk: true do |t|
      t.boolean :shared, default: false, null: false
      t.references :parent_service, foreign_key: { to_table: :database_services }, null: true
      t.datetime :over_quota_at, null: true
      t.integer :connection_limit, null: true
      t.integer :storage_mb_quota, null: true
      t.string :shared_role_name, null: true
      t.string :shared_db_name, null: true
    end

    add_index :database_services, :shared
  end
end

class CreateAppDatabases < ActiveRecord::Migration[8.1]
  def change
    create_table :app_databases do |t|
      t.references :app_record, null: false, foreign_key: true
      t.references :database_service, null: false, foreign_key: true
      t.string :alias_name

      t.timestamps
    end

    add_index :app_databases, [:app_record_id, :database_service_id], unique: true
  end
end

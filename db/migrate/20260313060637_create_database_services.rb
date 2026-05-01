class CreateDatabaseServices < ActiveRecord::Migration[8.1]
  def change
    create_table :database_services do |t|
      t.references :server, null: false, foreign_key: true
      t.string :service_type
      t.string :name
      t.integer :status, default: 0

      t.timestamps
    end

    add_index :database_services, [ :server_id, :name ], unique: true
  end
end

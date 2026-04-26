class AddTierNameToDatabaseServices < ActiveRecord::Migration[8.1]
  def change
    add_column :database_services, :tier_name, :string, default: "mini", null: false
    add_index :database_services, :tier_name
  end
end

class AddUpgradeColumnsToDatabaseServices < ActiveRecord::Migration[8.1]
  def change
    add_column :database_services, :pending_destroy_at, :datetime
    add_column :database_services, :upgrade_source_id,  :uuid
    add_index  :database_services, :upgrade_source_id
    add_index  :database_services, :pending_destroy_at, where: "pending_destroy_at IS NOT NULL"
  end
end

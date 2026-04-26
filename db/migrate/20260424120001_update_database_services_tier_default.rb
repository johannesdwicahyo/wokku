class UpdateDatabaseServicesTierDefault < ActiveRecord::Migration[8.1]
  def change
    change_column_default :database_services, :tier_name, from: "mini", to: "basic"
  end
end

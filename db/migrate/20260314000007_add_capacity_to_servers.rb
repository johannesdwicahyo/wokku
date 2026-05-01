class AddCapacityToServers < ActiveRecord::Migration[8.1]
  def change
    add_column :servers, :capacity_total_mb, :integer, default: 0
    add_column :servers, :capacity_used_mb, :integer, default: 0
    add_column :servers, :region, :string
  end
end

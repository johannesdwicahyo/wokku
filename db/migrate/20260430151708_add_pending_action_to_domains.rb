class AddPendingActionToDomains < ActiveRecord::Migration[8.1]
  def change
    add_column :domains, :pending_action, :string
  end
end

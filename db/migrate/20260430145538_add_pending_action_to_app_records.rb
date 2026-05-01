class AddPendingActionToAppRecords < ActiveRecord::Migration[8.1]
  def change
    add_column :app_records, :pending_action, :string
  end
end

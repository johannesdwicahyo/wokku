class AddDeletionFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :deleted_at, :datetime
    add_column :users, :deletion_scheduled_at, :datetime
    add_index :users, :deleted_at
    add_index :users, :deletion_scheduled_at
  end
end

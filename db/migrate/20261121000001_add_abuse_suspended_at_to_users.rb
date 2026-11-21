class AddAbuseSuspendedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :abuse_suspended_at, :datetime
  end
end

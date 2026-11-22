class AddAbuseRepoOwnersToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :abuse_repo_owners, :string, array: true, default: [], null: false
  end
end

class AddGithubFields < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :github_installation_id, :bigint
    add_column :users, :github_username, :string
    add_column :app_records, :github_repo_full_name, :string
    add_column :app_records, :github_webhook_secret, :string

    add_index :users, :github_installation_id
    add_index :app_records, :github_repo_full_name
  end
end

class AddGitProviderToAppRecords < ActiveRecord::Migration[8.1]
  def change
    add_column :app_records, :git_provider, :string
    add_column :app_records, :git_repo_full_name, :string
    add_column :app_records, :git_webhook_secret, :string
  end
end

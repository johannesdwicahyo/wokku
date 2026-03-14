class AddGitRepositoryUrlToAppRecords < ActiveRecord::Migration[8.1]
  def change
    add_column :app_records, :git_repository_url, :string
  end
end

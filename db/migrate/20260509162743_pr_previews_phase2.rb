class PrPreviewsPhase2 < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :gitlab_access_token,        :string
    add_column :users, :gitlab_refresh_token,       :string
    add_column :users, :gitlab_token_expires_at,    :datetime
    add_column :users, :bitbucket_access_token,     :string
    add_column :users, :bitbucket_refresh_token,    :string
    add_column :users, :bitbucket_token_expires_at, :datetime

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE app_records
          SET git_provider = 'github',
              git_repo_full_name = github_repo_full_name
          WHERE github_repo_full_name IS NOT NULL
            AND git_provider IS NULL
        SQL
      end
    end

    add_index :app_records, [ :git_provider, :git_repo_full_name ],
              name: "index_app_records_on_provider_and_repo"
  end
end

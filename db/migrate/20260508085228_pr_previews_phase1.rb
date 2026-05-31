class PrPreviewsPhase1 < ActiveRecord::Migration[8.1]
  def change
    add_column :app_records, :preview_enabled,    :boolean, default: false, null: false
    add_column :app_records, :database_strategy,  :string,  default: "empty", null: false
    add_column :app_records, :billing_exempt,     :boolean, default: false, null: false
    add_column :app_records, :last_commit_sha,    :string
    add_column :app_records, :last_commit_at,     :datetime
    add_column :app_records, :preview_comment_id, :bigint

    add_index :app_records, [ :is_preview, :last_commit_at ]
    add_index :app_records, [ :is_preview, :team_id ]
    add_index :app_records, [ :parent_app_id, :pr_number ], unique: true,
              where: "is_preview = true",
              name: "index_app_records_on_parent_pr_unique"

    add_column :env_vars, :scope, :string, default: "both", null: false
    add_index  :env_vars, [ :app_record_id, :scope ]

    create_table :preview_dns_records do |t|
      t.references :app_record, null: false, foreign_key: true, index: { unique: true }, type: :uuid
      t.string :hostname, null: false
      t.string :cloudflare_record_id
      t.timestamps
    end
    add_index :preview_dns_records, :hostname, unique: true
  end
end

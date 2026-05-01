class AddPreviewFieldsToAppRecords < ActiveRecord::Migration[8.1]
  def change
    add_column :app_records, :is_preview, :boolean, default: false, null: false
    add_column :app_records, :pr_number, :integer
    add_reference :app_records, :parent_app, foreign_key: { to_table: :app_records }, null: true
    add_index :app_records, [ :parent_app_id, :pr_number ], unique: true, where: "is_preview = true"
  end
end

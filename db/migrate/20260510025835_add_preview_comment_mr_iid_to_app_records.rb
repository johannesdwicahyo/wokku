class AddPreviewCommentMrIidToAppRecords < ActiveRecord::Migration[8.1]
  def change
    add_column :app_records, :preview_comment_mr_iid, :integer
  end
end

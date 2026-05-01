class UuidDeploysReleaseId < ActiveRecord::Migration[8.1]
  # deploys.release_id had no foreign-key constraint, so the bulk swap
  # missed it. Drop the orphaned bigint column and replace with a real
  # uuid FK to releases.
  def up
    remove_column :deploys, :release_id
    add_reference :deploys, :release, type: :uuid, foreign_key: { on_delete: :nullify }, index: true
  end

  def down
    remove_reference :deploys, :release, foreign_key: true, index: true
    add_column :deploys, :release_id, :bigint
  end
end

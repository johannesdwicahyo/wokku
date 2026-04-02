class CreateReleases < ActiveRecord::Migration[8.1]
  def change
    create_table :releases do |t|
      t.references :app_record, null: false, foreign_key: true
      t.integer :version
      t.references :deploy, null: true, foreign_key: true
      t.string :description

      t.timestamps
    end

    add_index :releases, [ :app_record_id, :version ], unique: true
    add_foreign_key :deploys, :releases
  end
end

class CreateDeploys < ActiveRecord::Migration[8.1]
  def change
    create_table :deploys do |t|
      t.references :app_record, null: false, foreign_key: true
      t.references :release, null: true
      t.integer :status, default: 0
      t.string :commit_sha
      t.text :log
      t.datetime :started_at
      t.datetime :finished_at

      t.timestamps
    end
  end
end

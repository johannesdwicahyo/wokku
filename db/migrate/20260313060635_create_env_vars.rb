class CreateEnvVars < ActiveRecord::Migration[8.1]
  def change
    create_table :env_vars do |t|
      t.references :app_record, null: false, foreign_key: true
      t.string :key
      t.text :value

      t.timestamps
    end

    add_index :env_vars, [:app_record_id, :key], unique: true
  end
end

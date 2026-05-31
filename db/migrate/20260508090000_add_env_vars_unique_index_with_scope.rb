class AddEnvVarsUniqueIndexWithScope < ActiveRecord::Migration[8.1]
  def change
    # The original create_env_vars migration added a UNIQUE INDEX on
    # (app_record_id, key) which would prevent the multi-scope design
    # from supporting the same key under multiple scopes. Drop it
    # before adding the wider unique index.
    reversible do |dir|
      dir.up do
        if index_exists?(:env_vars, [ :app_record_id, :key ], unique: true)
          remove_index :env_vars, column: [ :app_record_id, :key ]
        end
      end
      dir.down do
        unless index_exists?(:env_vars, [ :app_record_id, :key ], unique: true)
          add_index :env_vars, [ :app_record_id, :key ], unique: true
        end
      end
    end

    add_index :env_vars, [ :app_record_id, :key, :scope ], unique: true
  end
end

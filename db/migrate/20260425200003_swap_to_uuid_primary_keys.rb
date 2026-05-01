class SwapToUuidPrimaryKeys < ActiveRecord::Migration[8.1]
  EXCLUDED_TABLES = %w[ar_internal_metadata schema_migrations solid_queue_blocked_executions
                       solid_queue_claimed_executions solid_queue_failed_executions
                       solid_queue_jobs solid_queue_pauses solid_queue_processes
                       solid_queue_ready_executions solid_queue_recurring_executions
                       solid_queue_recurring_tasks solid_queue_scheduled_executions
                       solid_queue_semaphores
                       solid_cache_entries
                       solid_cable_messages].freeze

  # Tables whose original FK column was NOT NULL — we re-apply that
  # constraint after swap. Detected dynamically below.
  def up
    fks = foreign_key_specs

    # Capture not-null and on-delete behavior before we drop FKs.
    fks.each do |spec|
      col = connection.columns(spec[:from_table]).find { |c| c.name == spec[:column] }
      spec[:not_null] = col && !col.null
      spec[:on_delete] = spec[:on_delete] # already populated from foreign_keys
    end

    # 1. Drop FK constraints, drop bigint FK column (auto-drops its index),
    #    rename the new uuid FK column, rename its index, restore NOT NULL.
    fks.each do |spec|
      from = quote_t(spec[:from_table])
      old  = quote_c(spec[:column])
      new_col = quote_c("#{spec[:column]}_new")
      new_idx = "index_#{spec[:from_table]}_on_#{spec[:column]}_new"
      final_idx = "index_#{spec[:from_table]}_on_#{spec[:column]}"

      execute "ALTER TABLE #{from} DROP CONSTRAINT IF EXISTS #{connection.quote_column_name(spec[:name])}" if spec[:name]
      execute "ALTER TABLE #{from} DROP COLUMN #{old}"
      execute "ALTER TABLE #{from} RENAME COLUMN #{new_col} TO #{old}"
      execute "ALTER INDEX IF EXISTS #{connection.quote_column_name(new_idx)} RENAME TO #{connection.quote_column_name(final_idx)}"
      execute "ALTER TABLE #{from} ALTER COLUMN #{old} SET NOT NULL" if spec[:not_null]
    end

    # 2. Drop bigint PK, drop intermediate id_new index (PK creates its own),
    #    rename id_new → id, install UUID PK + default.
    target_tables.each do |table|
      qt = quote_t(table)
      execute "ALTER TABLE #{qt} DROP CONSTRAINT IF EXISTS #{table}_pkey CASCADE"
      execute "DROP INDEX IF EXISTS index_#{table}_on_id_new"
      execute "ALTER TABLE #{qt} DROP COLUMN id"
      execute "ALTER TABLE #{qt} RENAME COLUMN id_new TO id"
      execute "ALTER TABLE #{qt} ADD PRIMARY KEY (id)"
      execute "ALTER TABLE #{qt} ALTER COLUMN id SET DEFAULT uuidv7()"
    end

    # 3. Re-add foreign key constraints with original on_delete actions.
    fks.each do |spec|
      add_foreign_key spec[:from_table], spec[:to_table],
                      column: spec[:column],
                      on_delete: spec[:on_delete]
    end

    # 4. Activities target_id polymorphic column: drop bigint, rename uuid.
    if connection.column_exists?(:activities, :target_id_new)
      execute "DROP INDEX IF EXISTS index_activities_on_target_type_and_target_id"
      execute "ALTER TABLE activities DROP COLUMN target_id"
      execute "ALTER TABLE activities RENAME COLUMN target_id_new TO target_id"
      execute "CREATE INDEX index_activities_on_target_type_and_target_id ON activities (target_type, target_id)"
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "UUID swap is one-way; restore from backup"
  end

  private

  def quote_t(t) = connection.quote_table_name(t)
  def quote_c(c) = connection.quote_column_name(c)

  def target_tables
    (connection.tables - EXCLUDED_TABLES).sort
  end

  def foreign_key_specs
    target_tables.flat_map do |table|
      connection.foreign_keys(table).map do |fk|
        next nil if EXCLUDED_TABLES.include?(fk.to_table.to_s)
        { from_table: table, column: fk.column, to_table: fk.to_table, name: fk.name, on_delete: fk.on_delete }
      end.compact
    end
  end

  def index_for(table, column)
    "index_#{table}_on_#{column}"
  end
end

class AddUuidColumnsToAllTables < ActiveRecord::Migration[8.1]
  EXCLUDED_TABLES = %w[ar_internal_metadata schema_migrations solid_queue_blocked_executions
                       solid_queue_claimed_executions solid_queue_failed_executions
                       solid_queue_jobs solid_queue_pauses solid_queue_processes
                       solid_queue_ready_executions solid_queue_recurring_executions
                       solid_queue_recurring_tasks solid_queue_scheduled_executions
                       solid_queue_semaphores
                       solid_cache_entries
                       solid_cable_messages].freeze

  def up
    target_tables.each do |table|
      next if connection.column_exists?(table, :id_new)
      execute "ALTER TABLE #{conn.quote_table_name(table)} ADD COLUMN id_new uuid NOT NULL DEFAULT uuidv7()"
      execute "CREATE UNIQUE INDEX index_#{table}_on_id_new ON #{conn.quote_table_name(table)} (id_new)"
    end

    # Add new uuid FK columns alongside existing bigint FKs
    foreign_key_specs.each do |spec|
      from = spec[:from_table]
      col_new = "#{spec[:column]}_new"
      next if connection.column_exists?(from, col_new)
      execute "ALTER TABLE #{conn.quote_table_name(from)} ADD COLUMN #{conn.quote_column_name(col_new)} uuid"
      execute "CREATE INDEX index_#{from}_on_#{col_new} ON #{conn.quote_table_name(from)} (#{conn.quote_column_name(col_new)})"
    end

    # Polymorphic-ish columns: activities.target_id is bigint but stores ids
    # from many tables. Add a uuid mirror so we can backfill it later.
    if connection.column_exists?(:activities, :target_id) && !connection.column_exists?(:activities, :target_id_new)
      execute "ALTER TABLE activities ADD COLUMN target_id_new uuid"
    end
  end

  def down
    target_tables.each do |table|
      execute "ALTER TABLE #{conn.quote_table_name(table)} DROP COLUMN IF EXISTS id_new"
    end
    foreign_key_specs.each do |spec|
      execute "ALTER TABLE #{conn.quote_table_name(spec[:from_table])} DROP COLUMN IF EXISTS #{conn.quote_column_name("#{spec[:column]}_new")}"
    end
    execute "ALTER TABLE activities DROP COLUMN IF EXISTS target_id_new" if connection.column_exists?(:activities, :target_id_new)
  end

  private

  def conn = connection

  def target_tables
    @target_tables ||= (connection.tables - EXCLUDED_TABLES).sort
  end

  def foreign_key_specs
    @foreign_key_specs ||= target_tables.flat_map do |table|
      connection.foreign_keys(table).map do |fk|
        next nil if EXCLUDED_TABLES.include?(fk.to_table.to_s)
        { from_table: table, column: fk.column, to_table: fk.to_table, name: fk.name }
      end.compact
    end
  end
end

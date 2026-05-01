class BackfillUuidForeignKeys < ActiveRecord::Migration[8.1]
  EXCLUDED_TABLES = %w[ar_internal_metadata schema_migrations solid_queue_blocked_executions
                       solid_queue_claimed_executions solid_queue_failed_executions
                       solid_queue_jobs solid_queue_pauses solid_queue_processes
                       solid_queue_ready_executions solid_queue_recurring_executions
                       solid_queue_recurring_tasks solid_queue_scheduled_executions
                       solid_queue_semaphores
                       solid_cache_entries
                       solid_cable_messages].freeze

  def up
    # The activities table has BEFORE-UPDATE triggers that block all
    # mutations in steady state. They have to be lifted while we
    # backfill uuid columns; restored at the end of this migration.
    activity_triggers = %w[activities_no_update activities_no_delete activities_no_truncate]
    activity_triggers.each { |t| execute "ALTER TABLE activities DISABLE TRIGGER #{t}" rescue nil }

    foreign_key_specs.each do |spec|
      from = quote_t(spec[:from_table])
      to   = quote_t(spec[:to_table])
      old  = quote_c(spec[:column])
      new_col  = quote_c("#{spec[:column]}_new")
      execute <<~SQL
        UPDATE #{from} f
        SET    #{new_col} = t.id_new
        FROM   #{to} t
        WHERE  f.#{old} = t.id;
      SQL
    end

    # Backfill activities.target_id_new by inspecting target_type and looking
    # up the corresponding row's id_new in the matching table. Wraps each
    # type in a single bulk update.
    target_types_in_activities.each do |type_name|
      table = type_name.tableize
      next unless connection.tables.include?(table)
      execute <<~SQL
        UPDATE activities a
        SET    target_id_new = t.id_new
        FROM   #{quote_t(table)} t
        WHERE  a.target_type = #{connection.quote(type_name)}
          AND  a.target_id   = t.id;
      SQL
    end

    activity_triggers.each { |t| execute "ALTER TABLE activities ENABLE TRIGGER #{t}" rescue nil }
  end

  def down
    foreign_key_specs.each do |spec|
      execute "UPDATE #{quote_t(spec[:from_table])} SET #{quote_c("#{spec[:column]}_new")} = NULL"
    end
    execute "UPDATE activities SET target_id_new = NULL"
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
        { from_table: table, column: fk.column, to_table: fk.to_table }
      end.compact
    end
  end

  def target_types_in_activities
    return [] unless connection.tables.include?("activities") &&
                     connection.column_exists?(:activities, :target_type)
    connection.select_values("SELECT DISTINCT target_type FROM activities WHERE target_type IS NOT NULL").compact
  end
end

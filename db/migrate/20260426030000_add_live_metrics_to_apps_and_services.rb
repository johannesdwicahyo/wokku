class AddLiveMetricsToAppsAndServices < ActiveRecord::Migration[8.1]
  # Pages render from these columns instead of opening per-render SSH probes.
  # MetricsPollJob writes them once per minute per server in a single SSH
  # round-trip — scaling cost is now linear in servers, not user × app × view.
  def change
    add_column :app_records, :live_cpu_pct,         :decimal, precision: 6, scale: 2
    add_column :app_records, :live_mem_used_mb,     :integer
    add_column :app_records, :live_mem_limit_mb,    :integer
    add_column :app_records, :live_container_count, :integer
    add_column :app_records, :live_metrics_at,      :datetime

    add_column :database_services, :live_db_bytes,    :bigint
    add_column :database_services, :live_mem_used_mb, :integer
    add_column :database_services, :live_metrics_at,  :datetime
  end
end

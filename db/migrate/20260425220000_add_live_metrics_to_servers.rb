class AddLiveMetricsToServers < ActiveRecord::Migration[8.1]
  def change
    add_column :servers, :live_cpu_pct, :decimal, precision: 6, scale: 2
    add_column :servers, :live_mem_used_mb, :integer
    add_column :servers, :live_mem_total_mb, :integer
    add_column :servers, :live_container_count, :integer
    add_column :servers, :live_metrics_at, :datetime
  end
end

class MetricsPollJob < ApplicationJob
  include Notifiable

  queue_as :metrics

  # One SSH round-trip per server, every minute. Aggregates docker stats for
  # all containers on the host and writes live_* columns on Server,
  # AppRecord, and DatabaseService. Pages read those columns — no SSH at
  # render time. Scaling cost is linear in servers, constant in users.
  def perform(server_id)
    server = Server.find(server_id)

    # Use root SSH to access docker stats (dokku user has a restricted shell).
    # The provision script authorizes the same ssh_private_key for root.
    output = Net::SSH.start(
      server.host,
      "root",
      port: server.port,
      non_interactive: true,
      timeout: 15,
      key_data: Array(server.ssh_private_key).reject(&:blank?)
    ) do |ssh|
      ssh.exec!("docker stats --no-stream --format '{{json .}}'")
    end

    server_cpu_total = 0.0
    server_mem_used  = 0
    server_mem_limit = 0
    container_count  = 0

    apps_by_name = server.app_records.index_by(&:name)
    app_buckets = Hash.new { |h, k| h[k] = { cpu: 0.0, mem_used: 0, mem_limit: 0, count: 0 } }

    # Service container names look like dokku.<type>.<name>. RAM comes from
    # docker stats; DB size needs a separate inline psql per postgres svc.
    service_ram_used = {}

    output.to_s.each_line do |line|
      data = JSON.parse(line) rescue nil
      next unless data
      container_count += 1

      mem_parts = data["MemUsage"].to_s.split("/")
      cpu_pct  = data["CPUPerc"].to_f
      mem_used = parse_bytes(mem_parts.first.to_s.strip)
      mem_lim  = parse_bytes(mem_parts.last.to_s.strip)

      server_cpu_total += cpu_pct
      server_mem_used  += mem_used
      server_mem_limit += mem_lim

      container_name = data["Name"].to_s
      if container_name.start_with?("dokku.")
        _, type, *name_parts = container_name.split(".")
        service_ram_used[[ type, name_parts.join(".") ]] = mem_used
      else
        app_name = container_name.split(".").first
        next unless app_name
        if (app = apps_by_name[app_name])
          b = app_buckets[app]
          b[:cpu]       += cpu_pct
          b[:mem_used]  += mem_used
          b[:mem_limit] += mem_lim
          b[:count]     += 1

          # Per-container metric history (kept for charts).
          app.metrics.create!(
            cpu_percent: cpu_pct,
            memory_usage: mem_used,
            memory_limit: mem_lim,
            recorded_at: Time.current
          )

          check_threshold(app, "resource_high_cpu", cpu_pct, 80.0)
          mem_pct = mem_lim > 0 ? (mem_used.to_f / mem_lim * 100) : 0
          check_threshold(app, "resource_high_memory", mem_pct, 90.0)
        end
      end
    end

    now = Time.current
    app_buckets.each do |app, b|
      app.update_columns(
        live_cpu_pct: b[:cpu].round(2),
        live_mem_used_mb: b[:mem_used] / (1024 * 1024),
        live_mem_limit_mb: b[:mem_limit] / (1024 * 1024),
        live_container_count: b[:count],
        live_metrics_at: now
      )
    end

    persist_service_metrics(server, service_ram_used, now)

    server.update_columns(
      live_cpu_pct: server_cpu_total.round(2),
      live_mem_used_mb: server_mem_used / (1024 * 1024),
      live_mem_total_mb: server_mem_limit / (1024 * 1024),
      live_container_count: container_count,
      live_metrics_at: now
    )
  rescue Net::SSH::Exception, Errno::ECONNREFUSED, JSON::ParserError => e
    Rails.logger.warn("MetricsPollJob failed for server #{server_id}: #{e.message}")
  end

  private

  # For each dedicated DatabaseService on the server, persist live RAM (from
  # docker stats) and live DB size (from inline psql per postgres svc).
  # One bad service shouldn't drop the whole batch. Shared tenants are
  # governed by SharedDatabaseQuotaJob.
  def persist_service_metrics(server, ram_by_service, now)
    server.database_services.where(shared: false).find_each do |svc|
      ram_used = ram_by_service[[ svc.service_type, svc.name ]]

      db_bytes = nil
      if svc.service_type == "postgres"
        client = Dokku::Client.new(server)
        db_bytes = Dokku::DatabaseResources.new(client).database_size_bytes(svc.service_type, svc.name)
      end

      svc.update_columns(
        live_db_bytes: db_bytes,
        live_mem_used_mb: ram_used ? ram_used / (1024 * 1024) : nil,
        live_metrics_at: now
      )
    rescue StandardError => e
      Rails.logger.warn("MetricsPollJob: service probe failed for #{svc.name}: #{e.message}")
    end
  end

  def check_threshold(app, event, value, threshold)
    cache_key = "alert:#{app.id}:#{event}"
    if value > threshold
      count = Rails.cache.increment(cache_key, 1, expires_in: 1.hour)
      if count == 2
        fire_resource_alert(app.team, event, app)
        Rails.cache.write(cache_key, 0, expires_in: 1.hour)
      end
    else
      Rails.cache.delete(cache_key)
    end
  end

  def parse_bytes(str)
    num = str.to_f
    case str
    when /GiB/i then (num * 1024 * 1024 * 1024).to_i
    when /MiB/i then (num * 1024 * 1024).to_i
    when /KiB/i then (num * 1024).to_i
    else num.to_i
    end
  end
end

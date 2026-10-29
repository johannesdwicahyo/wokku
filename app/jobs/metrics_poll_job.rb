class MetricsPollJob < ApplicationJob
  include Notifiable

  queue_as :metrics

  # One SSH round-trip per server, every minute. Aggregates docker stats for
  # all containers on the host and writes live_* columns on Server,
  # AppRecord, and DatabaseService. Pages read those columns — no SSH at
  # render time. Scaling cost is linear in servers, constant in users.
  def perform(server_id)
    server = Server.find(server_id)

    # SSH as the platform host user (Hosts::Ssh.user) for docker stats —
    # the dokku user has a restricted shell.
    # Also fetch nproc on the same connection — docker stats CPUPerc is
    # %-per-core, so summing across containers needs to be divided by the
    # number of cores to express server load as a single host-wide %.
    output, ncpu, host_mem_total_mb = nil, 1, nil
    Net::SSH.start(
      server.host,
      Hosts::Ssh.user,
      port: server.port,
      non_interactive: true,
      timeout: 5,
      key_data: Array(server.ssh_private_key).reject(&:blank?)
    ) do |ssh|
      output = ssh.exec!("docker stats --no-stream --format '{{json .}}'")
      cores = ssh.exec!("nproc").to_s.strip.to_i
      ncpu = cores.positive? ? cores : 1
      # True physical host RAM. docker stats reports the host total as each
      # unlimited container's "limit", so summing those over-counts by
      # ~host×N — read MemTotal directly for an honest capacity denominator.
      host_mem_total_mb = parse_meminfo_total_mb(ssh.exec!("cat /proc/meminfo"))
    end

    server_cpu_total = 0.0
    server_mem_used  = 0
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

      container_name = data["Name"].to_s
      if container_name.start_with?("dokku.")
        _, type, *name_parts = container_name.split(".")
        service_ram_used[[ type, name_parts.join(".") ]] = mem_used
      else
        if (app = Hosts::ContainerNames.app_for(container_name, apps_by_name))
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

    server_attrs = {
      live_cpu_pct: (server_cpu_total / ncpu).round(2),
      live_mem_used_mb: server_mem_used / (1024 * 1024),
      live_container_count: container_count,
      live_metrics_at: now
    }
    # Only overwrite the capacity denominator when we actually read MemTotal,
    # so a transient meminfo failure doesn't zero out a known-good value.
    if host_mem_total_mb&.positive?
      server_attrs[:live_mem_total_mb] = host_mem_total_mb
      server_attrs[:capacity_total_mb] = host_mem_total_mb
    end
    server.update_columns(server_attrs)
  rescue Net::SSH::Exception, Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::ETIMEDOUT, Errno::EHOSTUNREACH, Errno::ENETUNREACH, SocketError, IOError, JSON::ParserError => e
    Rails.logger.warn("MetricsPollJob failed for server #{server_id}: #{e.message}")
    if defined?(Sentry)
      Sentry.capture_exception(e, level: :warning, extra: {
        server_id: server_id,
        host: server&.host,
        port: server&.port,
        errno: e.class.name
      })
    end
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
      db_bytes = postgres_size_bytes(svc) if svc.service_type == "postgres"

      svc.update_columns(
        live_db_bytes: db_bytes,
        live_mem_used_mb: ram_used ? ram_used / (1024 * 1024) : nil,
        live_metrics_at: now
      )
    rescue StandardError => e
      Rails.logger.warn("MetricsPollJob: service probe failed for #{svc.name}: #{e.message}")
    end
  end

  # Live DB size for a dedicated postgres service — docker exec psql inside
  # the wokkud-managed container (W7 Phase 3: replaced the dokku
  # postgres:connect wire). The db inside the container is the UNDERSCORED
  # service name (DatabaseService#dedicated_db_name). nil on any failure so
  # one bad service doesn't drop the batch.
  def postgres_size_bytes(svc)
    out = Hosts::Ssh.new(svc.server).run_raw(
      "docker exec -i #{Shellwords.escape(svc.container_name)} " \
      "psql -U postgres -d #{Shellwords.escape(svc.dedicated_db_name)}",
      stdin: "SELECT pg_database_size(current_database());\n\\q\n"
    )
    out.to_s.lines.map(&:strip).find { |l| l.match?(/\A\d+\z/) }&.to_i
  rescue StandardError
    nil
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

  # Extract MemTotal (kB) from /proc/meminfo and convert to MB. Returns nil
  # if the line is missing/unreadable so callers can leave capacity alone.
  def parse_meminfo_total_mb(meminfo)
    kb = meminfo.to_s[/^MemTotal:\s+(\d+)\s*kB/i, 1]
    kb && (kb.to_i / 1024)
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

class MetricsPollJob < ApplicationJob
  include Notifiable

  queue_as :metrics

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

    output.to_s.each_line do |line|
      data = JSON.parse(line)
      container_name = data["Name"]
      app_name = container_name.split(".").first
      app = server.app_records.find_by(name: app_name)
      next unless app

      mem_parts = data["MemUsage"].split("/")
      app.metrics.create!(
        cpu_percent: data["CPUPerc"].to_f,
        memory_usage: parse_bytes(mem_parts.first.strip),
        memory_limit: parse_bytes(mem_parts.last.strip),
        recorded_at: Time.current
      )

      check_threshold(app, "resource_high_cpu", data["CPUPerc"].to_f, 80.0)
      mem_usage = parse_bytes(mem_parts.first.strip)
      mem_limit = parse_bytes(mem_parts.last.strip)
      mem_pct = mem_limit > 0 ? (mem_usage.to_f / mem_limit * 100) : 0
      check_threshold(app, "resource_high_memory", mem_pct, 90.0)
    end
  rescue Net::SSH::Exception, Errno::ECONNREFUSED, JSON::ParserError => e
    Rails.logger.warn("MetricsPollJob failed for server #{server_id}: #{e.message}")
  end

  private

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

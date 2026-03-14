class MetricsPollJob < ApplicationJob
  queue_as :metrics

  def perform(server_id)
    server = Server.find(server_id)

    # Use root SSH to access docker stats (dokku user can't run docker commands)
    output = Net::SSH.start(
      server.host,
      "root",
      port: server.port,
      non_interactive: true,
      timeout: 15
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
    end
  rescue Net::SSH::Exception, Errno::ECONNREFUSED, JSON::ParserError => e
    Rails.logger.warn("MetricsPollJob failed for server #{server_id}: #{e.message}")
  end

  private

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

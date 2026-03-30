module Dashboard
  class MetricsController < BaseController
    before_action :set_app

    def show
      authorize @app, :show?
      @processes = fetch_processes
      @resources = fetch_resources
      @container_stats = fetch_container_stats
      @metrics = @app.metrics.where("recorded_at > ?", 24.hours.ago).order(recorded_at: :asc)
    end

    private

    def set_app
      @app = AppRecord.find(params[:app_id])
    end

    def fetch_processes
      client = Dokku::Client.new(@app.server)
      output = client.run("ps:report #{@app.name}")
      processes = []
      output.each_line do |line|
        line = line.strip
        if (match = line.match(/Status (\w+) (\d+):\s+(\w+)\s*\(CID:\s*(\w+)\)/))
          processes << {
            type: match[1],
            index: match[2].to_i,
            status: match[3],
            container_id: match[4]
          }
        end
      end
      processes
    rescue => e
      Rails.logger.warn "Failed to fetch processes for #{@app.name}: #{e.message}"
      []
    end

    def fetch_resources
      client = Dokku::Client.new(@app.server)
      output = client.run("resource:report #{@app.name}")
      result = {}
      output.each_line do |line|
        stripped = line.strip
        next if stripped.blank? || stripped.start_with?("=")
        idx = stripped.rindex(":")
        next unless idx
        key = stripped[0...idx].strip.parameterize(separator: "_")
        value = stripped[(idx + 1)..].strip
        result[key] = value
      end
      result
    rescue => e
      Rails.logger.warn "Failed to fetch resources for #{@app.name}: #{e.message}"
      {}
    end

    def fetch_container_stats
      server = @app.server
      output = Net::SSH.start(
        server.host,
        "root",
        port: server.port,
        non_interactive: true,
        timeout: 10
      ) do |ssh|
        ssh.exec!("docker stats --no-stream --format '{{json .}}'")
      end

      stats = []
      output.to_s.each_line do |line|
        data = JSON.parse(line)
        container_name = data["Name"]
        # Match containers belonging to this app (e.g. "myapp.web.1")
        next unless container_name.start_with?("#{@app.name}.")

        stats << {
          name: container_name,
          cpu_percent: data["CPUPerc"].to_f,
          mem_usage: data["MemUsage"],
          mem_percent: data["MemPerc"].to_f,
          net_io: data["NetIO"],
          block_io: data["BlockIO"],
          pids: data["PIDs"]
        }
      end
      stats
    rescue Net::SSH::AuthenticationFailed
      @metrics_error = "Authentication failed. Root SSH access is required for container metrics. The server is configured with user '#{@app.server.ssh_user || 'dokku'}' — add a root SSH key to enable metrics."
      []
    rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT, Net::SSH::ConnectionTimeout
      @metrics_error = "Could not connect to server #{@app.server.host}. Check that the server is online and SSH port #{@app.server.port} is accessible."
      []
    rescue => e
      Rails.logger.warn "Failed to fetch container stats for #{@app.name}: #{e.message}"
      @metrics_error = "Failed to fetch metrics: #{e.message}"
      []
    end
  end
end

module Dashboard
  class MetricsController < BaseController
    before_action :set_app

    def show
      authorize @app, :show?
      @processes = fetch_processes
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


    def fetch_container_stats
      server = @app.server
      # docker stats requires an unrestricted shell. The `dokku` user is forced
      # to a dokku-wrapper command, so we SSH as root — the provision script
      # authorizes the same ssh_private_key for root as for dokku.
      output = Net::SSH.start(
        server.host,
        "root",
        port: server.port,
        non_interactive: true,
        timeout: 10,
        key_data: Array(server.ssh_private_key).reject(&:blank?)
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
      @metrics_error = "Root SSH refused the stored key. Re-run scripts/provision-dokku-server.sh on #{@app.server.host} (or copy dokku's pubkey into /root/.ssh/authorized_keys) so the metrics collector can run docker stats."
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

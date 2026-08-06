module Dashboard
  class MetricsController < BaseController
    before_action :set_app

    def show
      authorize @app, :show?
      return render_deferred_fragment if params[:deferred]

      # Shell branch: only cheap DB assigns (no SSH).
      @metrics = @app.metrics.where("recorded_at > ?", 24.hours.ago).order(recorded_at: :asc)
    end

    private

    def render_deferred_fragment
      @processes = fetch_processes
      @container_stats = fetch_container_stats
      render partial: "dashboard/metrics/frame", layout: false
    end

    def set_app
      @app = AppRecord.find(params[:app_id])
    end

    # Reads Swarm task state fanned out from the wokkud heartbeat
    # (app_records.live_containers) — no SSH (resources_controller pattern).
    def fetch_processes
      Array(@app.live_containers)
        .group_by { |c| c["process"] }
        .flat_map do |type, tasks|
          next [] if type.blank?
          tasks.each_with_index.map do |task, i|
            {
              type: type,
              index: i + 1,
              status: task["state"].to_s,
              # Swarm task ids aren't fanned out in live_containers; the
              # view renders this blank for wokkud apps.
              container_id: nil
            }
          end
        end
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
      @metrics_error = "Root SSH refused the stored key on #{@app.server.host}. Re-run wokkud/deploy/install.sh (or restore the control-plane key in /root/.ssh/authorized_keys) so the metrics collector can run docker stats."
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

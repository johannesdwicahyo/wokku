module Dashboard
  class AppsController < BaseController
    before_action :set_app, only: [ :show, :destroy, :restart, :stop, :start, :toggle_https, :toggle_maintenance ]

    def index
      @apps = policy_scope(AppRecord).main_apps.includes(:server, :team, :domains)
      @app = AppRecord.new
      @servers = policy_scope(Server)
    end

    def show
      authorize @app
      @releases = @app.releases.includes(:deploy).order(version: :desc).limit(5)
      @addons = @app.database_services.includes(:server)
      @domains = @app.domains
      @env_vars = @app.env_vars.order(:key)
      @processes = fetch_processes
      @container_stats = fetch_container_stats
      @resources = fetch_resources
      @current_allocation = defined?(DynoAllocation) ? @app.dyno_allocations.includes(:dyno_tier).find_by(process_type: "web") : nil
      @logs = fetch_logs
      @preview_apps = @app.preview_apps.order(pr_number: :desc) unless @app.is_preview?
    end

    def new
      @app = AppRecord.new
      @servers = policy_scope(Server)
    end

    def create
      team = current_team
      server = policy_scope(Server).find(params[:app_record][:server_id])
      @app = AppRecord.new(app_params.merge(team: team, creator: current_user, server: server))
      authorize @app

      if @app.save
        track("app.created", target: @app)
        redirect_to dashboard_app_path(@app), notice: "App created successfully."
      else
        @servers = policy_scope(Server)
        @apps = policy_scope(AppRecord).includes(:server, :team)
        render :index, status: :unprocessable_entity
      end
    end

    def destroy
      authorize @app
      begin
        client = Dokku::Client.new(@app.server)
        Dokku::Apps.new(client).destroy(@app.name)
      rescue Dokku::Client::CommandError, Dokku::Client::ConnectionError => e
        Rails.logger.warn("Failed to destroy #{@app.name} on Dokku: #{e.message}")
      end
      @app.destroy
      track("app.destroyed", target: @app)
      redirect_to dashboard_apps_path, notice: "App deleted successfully."
    end

    def restart
      authorize @app
      dokku_processes.restart(@app.name)
      @app.update(status: :running)
      track("app.restarted", target: @app)
      redirect_to dashboard_app_path(@app), notice: "#{@app.name} restarted."
    rescue => e
      redirect_to dashboard_app_path(@app), alert: "Restart failed: #{e.message}"
    end

    def stop
      authorize @app
      dokku_processes.stop(@app.name)
      @app.update(status: :stopped)
      track("app.stopped", target: @app)
      redirect_to dashboard_app_path(@app), notice: "#{@app.name} stopped."
    rescue => e
      redirect_to dashboard_app_path(@app), alert: "Stop failed: #{e.message}"
    end

    def start
      authorize @app
      dokku_processes.start(@app.name)
      @app.update(status: :running)
      track("app.started", target: @app)
      redirect_to dashboard_app_path(@app), notice: "#{@app.name} started."
    rescue => e
      redirect_to dashboard_app_path(@app), alert: "Start failed: #{e.message}"
    end

    def toggle_https
      authorize @app, :update?
      client = Dokku::Client.new(@app.server)
      client.run("redirect:set #{@app.name} https://#{@app.domains.first&.hostname || @app.name + '.wokku.dev'}")
      track("app.https_enabled", target: @app)
      redirect_to dashboard_app_path(@app), notice: "HTTPS redirect enabled."
    rescue => e
      redirect_to dashboard_app_path(@app), alert: "Failed: #{e.message}"
    end

    def toggle_maintenance
      authorize @app, :update?
      client = Dokku::Client.new(@app.server)
      begin
        output = client.run("maintenance:report #{@app.name}")
        enabled = output.include?("true")
        if enabled
          client.run("maintenance:disable #{@app.name}")
          track("app.maintenance_disabled", target: @app)
          redirect_to dashboard_app_path(@app), notice: "Maintenance mode disabled."
        else
          client.run("maintenance:enable #{@app.name}")
          track("app.maintenance_enabled", target: @app)
          redirect_to dashboard_app_path(@app), notice: "Maintenance mode enabled."
        end
      rescue => e
        redirect_to dashboard_app_path(@app), alert: "Failed: #{e.message}"
      end
    end

    private

    def set_app
      @app = AppRecord.find(params[:id])
    end

    def app_params
      params.require(:app_record).permit(:name, :deploy_branch)
    end

    def dokku_processes
      client = Dokku::Client.new(@app.server)
      Dokku::Processes.new(client)
    end

    def fetch_processes
      client = Dokku::Client.new(@app.server)
      output = client.run("ps:report #{@app.name}")
      processes = []
      output.each_line do |line|
        if (match = line.strip.match(/Status (\w+) (\d+):\s+(\w+)\s*\(CID:\s*(\w+)\)/))
          processes << { type: match[1], index: match[2].to_i, status: match[3], container_id: match[4] }
        end
      end
      processes
    rescue => e
      Rails.logger.warn "Failed to fetch processes: #{e.message}"
      []
    end

    def fetch_container_stats
      server = @app.server
      output = Net::SSH.start(server.host, "deploy", port: server.port, non_interactive: true, timeout: 10,
        key_data: server.ssh_private_key.present? ? [ server.ssh_private_key ] : nil) do |ssh|
        ssh.exec!("docker stats --no-stream --format '{{json .}}'")
      end
      stats = []
      output.to_s.each_line do |line|
        data = JSON.parse(line)
        next unless data["Name"].start_with?("#{@app.name}.")
        stats << { name: data["Name"], cpu_percent: data["CPUPerc"].to_f, mem_usage: data["MemUsage"],
                   mem_percent: data["MemPerc"].to_f, net_io: data["NetIO"], block_io: data["BlockIO"], pids: data["PIDs"] }
      end
      stats
    rescue => e
      Rails.logger.warn "Failed to fetch container stats: #{e.message}"
      []
    end

    def fetch_resources
      client = Dokku::Client.new(@app.server)
      output = client.run("resource:report #{@app.name}")
      result = {}
      output.each_line do |line|
        line = line.strip
        next if line.blank? || line.start_with?("=")
        idx = line.rindex(":")
        next unless idx
        key = line[0...idx].strip.parameterize(separator: "_")
        value = line[(idx + 1)..].strip
        result[key] = value if value.present?
      end
      result
    rescue => e
      {}
    end

    def fetch_logs
      client = Dokku::Client.new(@app.server)
      output = client.run("logs #{@app.name} --num 15")
      output.to_s.lines.map(&:strip).reject(&:blank?)
    rescue => e
      []
    end
  end
end

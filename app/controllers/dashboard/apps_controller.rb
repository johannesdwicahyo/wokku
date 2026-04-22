module Dashboard
  class AppsController < BaseController
    include PlanEnforceable
    before_action :enforce_free_container_limit!, only: [ :create ]
    before_action :set_app, only: [ :show, :destroy, :restart, :stop, :start, :toggle_https, :toggle_maintenance, :runtime_metrics_frame, :live_logs_frame, :resource_limits_frame ]

    def index
      @apps = policy_scope(AppRecord).main_apps.includes(:server, :team, :domains)
      @app = AppRecord.new
      @servers = policy_scope(Server)
    end

    def show
      authorize @app
      # SSH-backed data is deferred to Turbo Frame sub-requests so the
      # page itself renders from DB only and returns in <200 ms.
      # See #runtime_metrics_frame, #live_logs_frame, #resource_limits_frame.
      @releases = @app.releases.includes(:deploy).order(version: :desc).limit(5)
      @addons = @app.database_services.includes(:server)
      @domains = @app.domains
      @env_vars = @app.env_vars.order(:key)
      @current_allocation = defined?(DynoAllocation) ? @app.dyno_allocations.includes(:dyno_tier).find_by(process_type: "web") : nil
      @preview_apps = @app.preview_apps.order(pr_number: :desc) unless @app.is_preview?
      @maintenance_enabled = fetch_maintenance_enabled # cached 60 s
    end

    # Turbo-frame: CPU / memory / container count cards. One SSH call.
    def runtime_metrics_frame
      authorize @app, :show?
      @container_stats = fetch_container_stats
      render partial: "dashboard/apps/frames/runtime_metrics", layout: false
    end

    # Turbo-frame: live log tail + process stream labels. Two SSH calls.
    def live_logs_frame
      authorize @app, :show?
      @processes = fetch_processes
      @logs = fetch_logs
      render partial: "dashboard/apps/frames/live_logs", layout: false
    end

    # Turbo-frame: configured resource limits (Mem / CPU). One SSH call.
    def resource_limits_frame
      authorize @app, :show?
      @resources = fetch_resources
      render partial: "dashboard/apps/frames/resource_limits", layout: false
    end

    def new
      @app = AppRecord.new
      @servers = policy_scope(Server)
    end

    def create
      team = current_team
      server = policy_scope(Server).find(params[:app_record][:server_id])
      @app = AppRecord.new(app_params.merge(team: team, creator: current_user, server: server, status: :created))
      authorize @app

      if @app.save
        # Create DNS record: app-name.wokku.cloud → server IP
        Cloudflare::Dns.new.create_app_record(@app.name, server.host) rescue nil

        # Grant git push access to creator via Dokku ACL
        if current_user.ssh_public_keys.any?
          GrantAppAclJob.perform_later(@app.id, current_user.id)
        end

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
      # Clean up DNS record
      Cloudflare::Dns.new.delete_app_record(@app.name) rescue nil

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
      client.run("redirect:set #{@app.name} https://#{@app.domains.first&.hostname || @app.name + '.wokku.cloud'}")
      track("app.https_enabled", target: @app)
      redirect_to dashboard_app_path(@app), notice: "HTTPS redirect enabled."
    rescue => e
      redirect_to dashboard_app_path(@app), alert: "Failed: #{e.message}"
    end

    def toggle_maintenance
      authorize @app, :update?
      client = Dokku::Client.new(@app.server)
      begin
        if fetch_maintenance_enabled
          client.run("maintenance:disable #{@app.name}")
          track("app.maintenance_disabled", target: @app)
          notice = "Maintenance mode disabled."
        else
          client.run("maintenance:enable #{@app.name}")
          track("app.maintenance_enabled", target: @app)
          notice = "Maintenance mode enabled."
        end
        Rails.cache.delete(maintenance_cache_key)
        redirect_to dashboard_app_path(@app), notice: notice
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

    # Live maintenance state from Dokku. Cached for 60s to keep the show
    # page from paying an extra SSH round-trip on every refresh; the
    # toggle action busts the cache so the UI flips immediately.
    def fetch_maintenance_enabled
      Rails.cache.fetch(maintenance_cache_key, expires_in: 60.seconds) do
        output = Dokku::Client.new(@app.server).run("maintenance:report #{@app.name}")
        output.to_s.match?(/Maintenance enabled:\s+true/i)
      rescue StandardError => e
        Rails.logger.warn "Failed to fetch maintenance state for #{@app.name}: #{e.message}"
        false
      end
    end

    def maintenance_cache_key
      "app:#{@app.id}:maintenance_enabled"
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
      output = Net::SSH.start(server.host, "root", port: server.port, non_interactive: true, timeout: 10,
        key_data: Array(server.ssh_private_key).reject(&:blank?)) do |ssh|
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

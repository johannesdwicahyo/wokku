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

    # GET /dashboard/apps/check_name?name=foo
    # Returns { available, suggestions } for the New App modal's
    # live-validation field. Suggestions only computed when taken.
    def check_name
      raw = params[:name].to_s.strip.downcase
      sanitized = raw.gsub(/[^a-z0-9-]/, "").sub(/^-+/, "").sub(/-+$/, "")

      if sanitized.blank? || sanitized !~ /\A[a-z][a-z0-9-]*\z/
        return render json: {
          available: false,
          reason: "invalid",
          message: "Use lowercase letters, numbers, and hyphens. Must start with a letter."
        }
      end

      if AppRecord.exists?(name: sanitized)
        render json: {
          available: false,
          reason: "taken",
          suggestions: name_suggestions(sanitized)
        }
      else
        render json: { available: true, name: sanitized }
      end
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

    # Transfer app ownership to another user. The target's personal team
    # becomes the new owner, all open ResourceUsage segments close on the
    # transferring user and reopen on the target so daily debits flip
    # immediately. Linked databases follow the app — they're scoped to
    # the team via app_databases.
    def transfer
      authorize @app, :destroy?
      target_email = params[:email].to_s.strip.downcase
      target = User.find_by("LOWER(email) = ?", target_email)

      if target.nil?
        return redirect_to dashboard_app_path(@app), alert: "No user found with email #{target_email}."
      end
      if target == current_user
        return redirect_to dashboard_app_path(@app), alert: "App is already yours."
      end
      target_team = target.teams.first
      if target_team.nil?
        return redirect_to dashboard_app_path(@app), alert: "Target user has no team. Ask them to log in once first."
      end

      ActiveRecord::Base.transaction do
        @app.update!(team: target_team, created_by_id: target.id)
        # Close every open segment on the transferring user, reopen
        # under the target. Segment math (cost_cents_in_period) keeps the
        # historical rows intact — only future hours bill against target.
        rotate_app_segments(@app, target, at: Time.current)
        # Linked databases: their app_records.team_id changed via the
        # update above (cascades through app_databases). Rotate their
        # open segments too.
        @app.database_services.find_each { |db| rotate_db_segments(db, target, at: Time.current) }
      end

      track("app.transferred", target: @app, metadata: { from: current_user.email, to: target.email })
      Activity.log(user: target, team: target_team, action: "app.received_transfer",
                   target: @app, metadata: { from: current_user.email })
      redirect_to dashboard_apps_path, notice: "#{@app.name} transferred to #{target.email}."
    rescue ActiveRecord::RecordInvalid => e
      redirect_to dashboard_app_path(@app), alert: "Transfer failed: #{e.message}"
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

    # Close every open container ResourceUsage segment for this app and
    # reopen it under the target user. Segments freeze on close, so the
    # historical hours billed against the previous owner are preserved.
    def rotate_app_segments(app, new_owner, at:)
      app.dyno_allocations.includes(:dyno_tier).find_each do |alloc|
        ResourceUsage.where(resource_id_ref: alloc.resource_id_ref, stopped_at: nil)
                     .find_each { |u| u.stop!(at: at) }
        next unless alloc.dyno_tier
        ResourceUsage.create!(
          user_id: new_owner.id,
          resource_type: "container",
          resource_id_ref: alloc.resource_id_ref,
          tier_name: alloc.dyno_tier.name,
          price_cents_per_hour: alloc.dyno_tier.price_cents_per_hour * alloc.count,
          started_at: at,
          metadata: { app: app.name, process_type: alloc.process_type, count: alloc.count }
        )
      end
    end

    def rotate_db_segments(db, new_owner, at:)
      return if db.shared?
      ResourceUsage.where(resource_id_ref: "DatabaseService:#{db.id}", stopped_at: nil)
                   .find_each { |u| u.stop!(at: at) }
      rate = db.service_tier&.hourly_price_cents.to_f
      return if rate.zero?
      ResourceUsage.create!(
        user_id: new_owner.id,
        resource_type: "database",
        resource_id_ref: "DatabaseService:#{db.id}",
        tier_name: db.tier_name,
        price_cents_per_hour: rate,
        started_at: at,
        metadata: { name: db.name, type: db.service_type, app: db.app_records.first&.name }
      )
    end

    def app_params
      params.require(:app_record).permit(:name, :deploy_branch)
    end

    # Try a few stable variations before falling back to a random suffix.
    def name_suggestions(base, count: 3)
      adjectives = %w[bot api app web svc node]
      suggestions = []

      adjectives.each do |suffix|
        candidate = "#{base}-#{suffix}"
        suggestions << candidate if !AppRecord.exists?(name: candidate)
        break if suggestions.size >= count
      end

      while suggestions.size < count
        candidate = "#{base}-#{SecureRandom.hex(2)}"
        suggestions << candidate unless AppRecord.exists?(name: candidate)
      end

      suggestions
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

module Dashboard
  class AppsController < BaseController
    include Notifiable
    include PlanEnforceable

    rescue_from PlanEnforceable::PlanQuotaError do |e|
      redirect_to new_dashboard_app_path,
        alert: "Your #{current_user.plan.name} plan allows #{e.allowed} #{e.size} boxes; you already have #{e.requested - 1}. Upgrade or pick a smaller size."
    end

    before_action :reject_creation_during_deletion_pending, only: [ :create ]
    before_action :enforce_free_container_limit!, only: [ :create ]
    before_action :set_app, only: [ :show, :destroy, :restart, :stop, :start, :toggle_https, :toggle_maintenance, :toggle_cdn, :transfer, :unlock, :runtime_metrics_frame, :live_logs_frame, :resource_limits_frame ]

    def index
      # Pre-populate for the inline "+ NEW APP" modal so the modal can
      # render without a round-trip. Standalone /dashboard/apps/new still
      # works for direct links. Set FIRST so the rescue below can't leave
      # them nil — the modal renders on every successful index hit.
      @app     = AppRecord.new
      @servers = policy_scope(Server)
      @apps = policy_scope(AppRecord).main_apps
                .includes(:server, :team, :domains, dyno_allocations: :dyno_tier)
                .order(created_at: :desc)
      @plan = current_user.plan
      @box_usage = compute_box_usage(@apps)
      @recent_activity = Activity.where(target_type: "AppRecord", target_id: @apps.map(&:id))
                                 .order(created_at: :desc).limit(10)
    rescue StandardError
      @recent_activity = []
    end

    def show
      authorize @app
      # SSH-backed data is deferred to Turbo Frame sub-requests so the
      # page itself renders from DB only and returns in <200 ms.
      # See #runtime_metrics_frame, #live_logs_frame, #resource_limits_frame.
      @releases = @app.releases.includes(:deploy).order(version: :desc).limit(5)
      # Preload app_records so the per-addon billing share can divide by
      # link count without N+1 queries (shared addons split cost across
      # the apps they're linked to).
      @addons = @app.database_services.includes(:server, :app_records)
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
      @plan = current_user.current_plan
    end

    # GET /dashboard/apps/check_name?name=foo
    # Returns { available, suggestions } for the New App modal's
    # Session-authenticated app search for the topbar Stimulus controller.
    # `/api/v1/apps?q=` exists too but needs a Bearer token — the dashboard
    # uses cookies, so we expose a sibling JSON endpoint here.
    def search
      authorize AppRecord
      q = params[:q].to_s.strip
      apps = policy_scope(AppRecord).main_apps
      apps = apps.where("app_records.name ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(q)}%") if q.present?
      apps = apps.order(:name).limit(8)
      render json: apps.map { |a|
        {
          id: a.id,
          name: a.name,
          status: a.status,
          url: dashboard_app_path(a)
        }
      }
    end

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

      # Bundle v2: box_size drives both the quota check and the DynoTier.
      # Falls back to "sleeping" (free tier) so hand-rolled POSTs without
      # the new form field land on the cheapest available tier.
      box_size = params.dig(:app_record, :box_size).presence || "sleeping"
      shared_engines = params.dig(:app_record, :enabled_shared_engines) || []

      @app = AppRecord.new(
        app_params.merge(
          team: team,
          creator: current_user,
          server: server,
          status: :created,
          box_size: box_size,
          enabled_shared_engines: shared_engines
        )
      )
      authorize @app

      enforce_plan_quota!(current_user, size: box_size, additional: 1)

      if @app.save
        # Derive the DynoTier from box_size (Bundle v2 mapping).
        # Falls back to the cheapest non-capped tier if no mapping exists.
        tier_name = Plan::BOX_SIZE_TO_DYNO_TIER[box_size]
        chosen_tier = tier_name ? DynoTier.find_by(name: tier_name) : nil
        if chosen_tier&.at_cap_for?(current_user, exclude_app: @app)
          chosen_tier = DynoTier.order(:monthly_price_cents).find { |t| !t.at_cap_for?(current_user, exclude_app: @app) }
        end
        if chosen_tier
          @app.dyno_allocations.create!(process_type: "web", dyno_tier: chosen_tier, count: 1)
        end

        # Provision the Dokku-side app immediately so addons created
        # before the first `git push` can link successfully. Without
        # this, CreateAddonJob's `<plugin>:link` step fails with
        # "App <name> does not exist", the addon row gets rescue-destroyed,
        # and the user's left with an invisible orphan service on Dokku
        # and no UI feedback. Async via Solid Queue so a slow SSH
        # round-trip doesn't block the redirect.
        ProvisionDokkuAppJob.perform_later(@app.id)

        # Create DNS records on every enabled Wokku zone.
        Cloudflare::Dns.for_each_enabled { |dns| dns.create_app_record(@app.name, server.host) } rescue nil

        # Grant git push access to creator via Dokku ACL
        if current_user.ssh_public_keys.any?
          GrantAppAclJob.perform_later(@app.id, current_user.id)
        end

        # Bundle v2: provision dedicated DB/Redis requested at creation time.
        # These are non-fatal — the box is already saved, so any UpgradeError
        # surfaces as a warning flash rather than rolling back the create.
        dedicated_db_engine = params.dig(:app_record, :dedicated_db_engine).presence
        if dedicated_db_engine.present?
          begin
            DatabaseServiceUpgrade.call(app: @app, user: current_user, engine: dedicated_db_engine)
          rescue UpgradeError => e
            flash[:warning] = "App created, but dedicated #{dedicated_db_engine} could not be provisioned: #{e.message}"
          end
        end

        if params.dig(:app_record, :add_dedicated_redis).present?
          begin
            DatabaseServiceUpgrade.call(app: @app, user: current_user, engine: "redis")
          rescue UpgradeError => e
            flash[:warning] = "App created, but dedicated Redis could not be provisioned: #{e.message}"
          end
        end

        track("app.created", target: @app)
        fire_team_event(@app.team, "app_created", app_name: @app.name)
        # TODO: extract this first-app analytics guard to a shared concern at a 3rd callsite.
        # Activation-funnel "started" signal — fires on the user's first app (generic create has no deploy queued yet; the template path does).
        if current_user.app_records.count == 1
          flash[:posthog_event] = "first_deploy_started"
          flash[:posthog_props] = { app: @app.name }
        end
        redirect_to dashboard_app_path(@app), notice: "App created successfully."
      else
        @servers = policy_scope(Server)
        @apps = policy_scope(AppRecord).includes(:server, :team)
        render :index, status: :unprocessable_entity
      end
    end

    def destroy
      authorize @app
      client = Dokku::Client.new(@app.server) rescue nil

      # Snapshot exclusively-linked databases BEFORE we destroy the join rows.
      # An "exclusive" DB is one only this app uses — destroying the app
      # without destroying these would leave orphan postgres/redis services
      # racking up billing (Rp 500/day each).
      exclusive_dbs = @app.database_services.select { |db| db.app_records.where.not(id: @app.id).empty? }

      begin
        Dokku::Apps.new(client).destroy(@app.name) if client
      rescue Dokku::Client::CommandError, Dokku::Client::ConnectionError => e
        Rails.logger.warn("Failed to destroy #{@app.name} on Dokku: #{e.message}")
      end

      # Clean up DNS records on every Wokku zone.
      Cloudflare::Dns.for_each_enabled { |dns| dns.delete_app_record(@app.name) } rescue nil

      app_name = @app.name
      app_team = @app.team
      @app.destroy

      # Tear down the orphaned database services: drop the Dokku service
      # then destroy the DatabaseService record (its before_destroy closes
      # the billing segment so debits stop the same day).
      destroyed_db_names = []
      exclusive_dbs.each do |db|
        begin
          Dokku::Databases.new(client).destroy(db.service_type, db.name) if client
        rescue Dokku::Client::CommandError, Dokku::Client::ConnectionError => e
          Rails.logger.warn("Failed to destroy database #{db.name} on Dokku: #{e.message}")
        end
        db.destroy
        destroyed_db_names << db.name
      end

      track("app.destroyed", target: @app)
      fire_team_event(app_team, "app_deleted", app_name: app_name)

      notice = if destroyed_db_names.any?
        "App deleted. Also removed #{destroyed_db_names.size} linked #{'database'.pluralize(destroyed_db_names.size)}: #{destroyed_db_names.join(', ')}."
      else
        "App deleted successfully."
      end
      redirect_to dashboard_apps_path, notice: notice
    end

    # restart/stop/start used to be synchronous SSH calls that took up
    # to a minute (zero-downtime checks) and routinely gateway-timed-out
    # at kamal-proxy's 30s response cap. Now they enqueue
    # DokkuAppActionJob and redirect immediately so the user always
    # gets feedback; the runtime metrics frame on the show page picks
    # up the new state on its next refresh.
    def restart
      queue_app_action("restart")
    end

    def stop
      queue_app_action("stop")
    end

    def start
      queue_app_action("start")
    end

    # Set pending_action *before* enqueuing so the after_update_commit
    # broadcast fires synchronously (Solid Queue's perform_later may
    # complete the job before the controller returns). Same column gets
    # cleared by the job — that broadcasts back the normal frame.
    def queue_app_action(action)
      authorize @app, :update?
      @app.update(pending_action: action)
      DokkuAppActionJob.perform_later(@app.id, action)
      track("app.#{action}_queued", target: @app)
      redirect_to dashboard_app_path(@app)
    end

    # Release Dokku's deploy lock. Synchronous because apps:unlock is
    # a fast file-removal op (rm /home/dokku/<app>/dokku-deploy-lock),
    # well under the SSH timeout. Use when a previous git push got
    # interrupted (network drop, Docker Hub TLS timeout mid-pull) and
    # left the lock in place — every subsequent push then 503s with
    # "deploy lock in place; Run apps:unlock to release".
    def unlock
      authorize @app, :update?
      Dokku::Apps.new(Dokku::Client.new(@app.server)).unlock(@app.name)
      track("app.deploy_unlocked", target: @app)
      redirect_to dashboard_app_path(@app), notice: "Deploy lock released — git push should work again."
    rescue Dokku::Client::CommandError, Dokku::Client::ConnectionError => e
      redirect_to dashboard_app_path(@app), alert: "Couldn't release deploy lock: #{e.message.lines.first&.strip}"
    end

    # One-click backup of the app's primary database. Convenience route
    # for the BackupsSummaryCardComponent on the app overview tab —
    # users with multi-DB apps still drop into the addon-scoped flow.
    def backup_now
      authorize @app, :update?
      db = @app.primary_database

      if db.nil?
        return redirect_to dashboard_app_path(@app),
          alert: "Attach a database to this app before triggering a backup."
      end

      if db.backup_limit_reached?
        return redirect_to dashboard_app_path(@app),
          alert: "Free tier backup limit reached. Upgrade to Solo or Pro for daily backups with retention."
      end

      BackupJob.perform_later(db.id)
      track("app.backup_triggered", target: @app, metadata: { database_id: db.id })
      redirect_to dashboard_app_path(@app), notice: "Backup started — refresh in a moment to see it."
    end

    def toggle_https
      authorize @app, :update?
      client = Dokku::Client.new(@app.server)
      fallback_host = "#{@app.name}.#{Cloudflare::Dns.canonical_domain}"
      client.run("redirect:set #{@app.name} https://#{@app.domains.first&.hostname || fallback_host}")
      track("app.https_enabled", target: @app)
      redirect_to dashboard_app_path(@app), notice: "HTTPS redirect enabled."
    rescue => e
      redirect_to dashboard_app_path(@app), alert: "Failed: #{e.message}"
    end

    # Flip the Cloudflare proxy on the app's DNS record. Persists the
    # intended state immediately so the UI reflects the user's choice;
    # the actual CF API call happens in UpdateAppCdnJob which rolls
    # back the DB flag if the call fails.
    def toggle_cdn
      authorize @app, :update?
      new_state = !@app.cloudflare_proxied?
      @app.update!(cloudflare_proxied: new_state)
      UpdateAppCdnJob.perform_later(@app.id, new_state)
      msg = new_state ? "Cloudflare CDN turning on (DNS propagation may take a minute)." : "Cloudflare CDN turning off."
      redirect_to dashboard_app_path(@app), notice: msg
    end

    # Initiate a pending transfer. Nothing flips until the target accepts
    # the request from their email; until then the source still owns the
    # app and is still being billed. See AppTransfersController#accept for
    # the actual ownership swap (delegates to AppOwnershipTransfer).
    def transfer
      authorize @app, :destroy?

      # GET renders the per-app transfer form + any pending outgoing
      # transfer (Phase 3 backlog #7 — Settings sub-nav 'transfer' section).
      if request.get?
        @pending_transfer = AppTransfer.pending.where(app_record: @app)
                                       .where("expires_at > ?", Time.current).first
        return render :transfer
      end

      target_email = params[:email].to_s.strip.downcase
      target = User.find_by("LOWER(email) = ?", target_email)

      if target.nil?
        return redirect_to dashboard_app_path(@app), alert: "No user found with email #{target_email}."
      end
      if target == current_user
        return redirect_to dashboard_app_path(@app), alert: "App is already yours."
      end
      if target.teams.first.nil?
        return redirect_to dashboard_app_path(@app), alert: "Target user has no team. Ask them to log in once first."
      end
      if AppTransfer.pending.where(app_record: @app).where("expires_at > ?", Time.current).exists?
        return redirect_to dashboard_app_path(@app), alert: "A transfer for this app is already pending. Cancel it before starting a new one."
      end

      transfer_record = AppTransfer.create!(
        app_record: @app,
        from_user: current_user,
        to_user: target
      )

      AppTransferMailer.with(transfer: transfer_record).request_email.deliver_later

      track("app.transfer_requested", target: @app, metadata: { from: current_user.email, to: target.email })
      redirect_to dashboard_app_path(@app), notice: "Transfer request sent to #{target.email}. Ownership will move once they accept."
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

    def compute_box_usage(apps)
      usage = Hash.new(0)
      apps.each do |app|
        app.dyno_allocations.each do |alloc|
          size = alloc.dyno_tier&.size_key
          usage[size] += alloc.count if size
        end
      end
      usage
    end

    def set_app
      @app = AppRecord.find(params[:id])
    end

    def app_params
      # :dedicated_db_engine and :add_dedicated_redis are controller-only params —
      # they're not AppRecord columns and are handled directly in #create.
      params.require(:app_record).permit(:name, :deploy_branch, :box_size, enabled_shared_engines: [])
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
        # Skip ephemeral deploy/upcoming containers — they exist briefly during
        # a release. Including them inflated both the displayed count and the
        # memory limit (tier_limit × N containers), confusing users.
        next if data["Name"].match?(/\.(upcoming|deploy)-/)
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

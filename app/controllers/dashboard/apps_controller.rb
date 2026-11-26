module Dashboard
  class AppsController < BaseController
    include Notifiable
    include PlanEnforceable
    include OnboardingTourable
    include Deferrable

    deferred_sections :list, :side, :panel_deploys, :panel_logs

    rescue_from PlanEnforceable::AccountLimitError do |e|
      redirect_to new_dashboard_app_path, alert: e.message
    end

    rescue_from PlanEnforceable::PlanQuotaError do |e|
      redirect_to new_dashboard_app_path,
        alert: "Your #{current_user.plan.name} plan allows #{e.allowed} #{e.size} boxes; you already have #{e.requested - 1}. Upgrade or pick a smaller size."
    end

    before_action :run_onboarding_waypoints, only: [ :index ]
    before_action :reject_creation_during_deletion_pending, only: [ :create ]
    before_action :enforce_free_container_limit!, only: [ :create ]
    before_action :set_app, only: [ :show, :destroy, :restart, :stop, :start, :toggle_https, :toggle_maintenance, :toggle_cdn, :transfer, :danger, :backup_now, :unlock, :lock, :panel, :update_deploy_branch ]

    def index
      # Instant shell: only the cheap existence check + the inline
      # "+ NEW APP" modal data. The heavy apps/box-usage/activity queries
      # run in the deferred sections (load_list / load_side).
      @app       = AppRecord.new
      @servers   = policy_scope(Server)
      @has_apps  = policy_scope(AppRecord).main_apps.exists?
      # Per-size remaining-quota snapshot for the new-app modal's box picker.
      # Shares one source of truth with enforce_plan_quota! so the form never
      # offers a size that `create` would reject.
      @box_quota = box_picker_state(current_user)
      @deleting_id = params[:deleting].presence
      @deletion = ::Apps::DeletionProgress.for(@deleting_id, current_user) if @deleting_id
    end

    def show
      authorize @app
      # Newest 20 (all with :deploy): enough to find the current release and a
      # rollback target; header and timeline show only the newest few.
      @releases = @app.releases.includes(:deploy).order(version: :desc).limit(20).to_a
      @current_release = Organisms::AppHeaderComponent.current_release(@releases)
      @domains = @app.domains.to_a
      @stats = ::Apps::DetailStats.for(@app)
    end

    # Record panel: read-only drawer opened from an apps-table row. The
    # body's deploys/logs sections are lazy turbo-frames (load_panel_deploys
    # / load_panel_logs below) — this action only needs the cheap counts.
    def panel
      authorize @app, :show?
      @domains_count   = @app.domains.count
      @databases_count = @app.app_databases.count
      render layout: false
    end

    # Inline record-panel edit (U5 locked decision #1): deploy_branch is the
    # ONE safe click-to-edit field — a plain column with no fleet side
    # effects, it only affects the next deploy. No converge/job here.
    def update_deploy_branch
      authorize @app, :update?
      branch = params.require(:app_record).permit(:deploy_branch)[:deploy_branch].to_s.strip
      @app.update(deploy_branch: branch) if branch.present?
      redirect_to panel_dashboard_app_path(@app)
    end

    def new
      @app = AppRecord.new
      @servers = policy_scope(Server)
      @plan = current_user.current_plan
      @box_quota = box_picker_state(current_user)
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

      # Per-resource billing (spec 2026-09-24 §5.3): the builder posts
      # processes[web][...] instead of a box_size — skip the tier picker
      # entirely and size the app via Resources::ApplyChange after save.
      builder_mode = Wokku.config.resource_builder? && params[:processes].present?

      # Bundle v2: box_size drives both the quota check and the DynoTier.
      # Falls back to "sleeping" (free tier) so hand-rolled POSTs without
      # the new form field land on the cheapest available tier.
      box_size = nil
      unless builder_mode
        requested_size = params.dig(:app_record, :box_size).presence || "sleeping"
        box_size = resolve_box_size(current_user, required: requested_size)
      end
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
      # B6 W2: native apps are born without a dokku shell, fully flagged.
      if AppRecord.native_creates?
        @app.assign_attributes(wokkud_native: true, wokkud_routed: true, wokkud_git: true, wokkud_lifecycle: true)
      end
      authorize @app

      repo_url = params.dig(:app_record, :git_repository_url).to_s.strip.presence
      if repo_url && !RepoUrlDeployJob.valid_url?(repo_url)
        @app.errors.add(:base, "Repository must be a public https:// address (for example https://github.com/you/your-app).")
        @servers  = policy_scope(Server)
        @has_apps = policy_scope(AppRecord).main_apps.exists?
        return render :index, status: :unprocessable_entity
      end

      enforce_plan_quota!(current_user, size: box_size, additional: 1) unless builder_mode

      if @app.save
        if builder_mode
          # Runs before any DNS/provisioning side effect: a refused size
          # un-creates the app and re-renders the form with the reason.
          result = Resources::ApplyChange.call(app: @app, user: current_user, processes: params[:processes])
          unless result.ok
            @app.destroy!
            @app.errors.add(:base, result.error)
            @servers  = policy_scope(Server)
            @has_apps = policy_scope(AppRecord).main_apps.exists?
            return render :index, status: :unprocessable_entity
          end
        else
          # Derive the DynoTier from box_size (Bundle v2 mapping).
          # Falls back to the cheapest non-capped tier if no mapping exists.
          tier_name = DynoTier::BOX_SIZE_TO_DYNO_TIER[box_size]
          chosen_tier = tier_name ? DynoTier.find_by(name: tier_name) : nil
          if chosen_tier&.at_cap_for?(current_user, exclude_app: @app)
            chosen_tier = DynoTier.order(:monthly_price_cents).find { |t| !t.at_cap_for?(current_user, exclude_app: @app) }
          end
          if chosen_tier
            @app.dyno_allocations.create!(process_type: "web", dyno_tier: chosen_tier, count: 1)
          end
        end

        # Create the DNS record in the canonical zone only (wokku.app once
        # WOKKU_APP_ENABLED flips, wokku.cloud today) — new apps no longer
        # mint a second record in the zone being phased out.
        Wokku.config.dns_provider.create_app_record(@app.name, server.host) rescue nil

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

        if repo_url
          @app.update_column(:git_repository_url, repo_url)
          deploy = @app.deploys.create!(status: :pending)
          @app.releases.create!(deploy: deploy, description: "Deploy from #{repo_url}".truncate(200))
          RepoUrlDeployJob.perform_later(app_id: @app.id, deploy_id: deploy.id, url: repo_url, branch: @app.deploy_branch.presence || "main")
          return redirect_to dashboard_app_deploy_path(@app, deploy), notice: "Building #{repo_url}…"
        end
        # TODO: extract this first-app analytics guard to a shared concern at a 3rd callsite.
        # Activation-funnel "started" signal — fires on the user's first app (generic create has no deploy queued yet; the template path does).
        if current_user.app_records.count == 1
          flash[:posthog_event] = "first_deploy_started"
          flash[:posthog_props] = { app: @app.name }
        end
        redirect_to dashboard_app_path(@app), notice: "App created successfully."
      else
        @servers   = policy_scope(Server)
        @has_apps  = policy_scope(AppRecord).main_apps.exists?
        render :index, status: :unprocessable_entity
      end
    end

    def destroy
      authorize @app

      # ::-prefixed: app/controllers/dashboard/apps/ (Dashboard::Apps) shadows
      # the top-level Apps module from inside Dashboard::AppsController.
      ::Apps::Destroyer.ensure_idle!(@app)
      ::Apps::DeletionProgress.start!(@app)
      AppDestroyJob.perform_later(@app.id)

      track("app.destroyed", target: @app)
      fire_team_event(@app.team, "app_deleted", app_name: @app.name)
      # The apps page shows the live progress overlay for ?deleting=.
      redirect_to dashboard_apps_path(deleting: @app.id)
    rescue ::Lifecycle::Ops::Busy
      redirect_to dashboard_app_path(@app), alert: "A deploy is in progress. Wait for it to finish, then delete the app."
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
      if action != "stop" && !@app.run_allowed?
        return redirect_to dashboard_app_path(@app), alert: AppRecord::RUN_BLOCKED_MESSAGE
      end
      @app.update(pending_action: action)
      DokkuAppActionJob.perform_later(@app.id, action)
      track("app.#{action}_queued", target: @app)
      redirect_to dashboard_app_path(@app)
    end

    # Release the deploy lock (control-plane state — see
    # Apps::Lifecycle::DeployLock). Use when a previous deploy got
    # interrupted and left the lock in place.
    def unlock
      authorize @app, :update?
      ::Apps::Lifecycle::DeployLock.new(@app).unlock!
      Activity.log(user: current_user, team: current_team, action: "app.unlocked", target: @app)
      redirect_to dashboard_app_path(@app), notice: "Deploy lock released — git push should work again."
    rescue ::Apps::Lifecycle::Error => e
      msg = if e.message.to_s.match?(/Unable to remove deploy lock/i)
        "Couldn't release the lock — a deploy or rebuild may be in progress. If the app is crash-looping it's being auto-stopped; otherwise try again in a minute."
      else
        "Couldn't release deploy lock: #{e.message.lines.first&.strip}"
      end
      redirect_to dashboard_app_path(@app), alert: msg
    end

    def lock
      authorize @app, :update?
      ::Apps::Lifecycle::DeployLock.new(@app).lock!
      Activity.log(user: current_user, team: current_team, action: "app.locked", target: @app)
      redirect_to dashboard_app_path(@app), notice: "Deploy lock set — git push will refuse until you unlock."
    rescue ::Apps::Lifecycle::Error => e
      redirect_to dashboard_app_path(@app), alert: "Couldn't set deploy lock: #{e.message.lines.first&.strip}"
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

      if db.backups_unsupported?
        return redirect_to dashboard_app_path(@app), alert: db.backups_unsupported_message
      end

      if db.backup_limit_reached?
        return redirect_to dashboard_app_path(@app),
          alert: db.backup_limit_message
      end

      BackupJob.perform_later(db.id)
      track("app.backup_triggered", target: @app, metadata: { database_id: db.id })
      redirect_to dashboard_app_path(@app), notice: "Backup started — refresh in a moment to see it."
    end

    def toggle_https
      authorize @app, :update?
      toggle = ::Apps::Settings::HttpsToggle.new(@app)
      if toggle.enabled?
        toggle.disable!
        Activity.log(user: current_user, team: current_team, action: "app.https_disabled", target: @app)
        redirect_to dashboard_app_path(@app), notice: "HTTPS redirect disabled."
      else
        toggle.enable!
        Activity.log(user: current_user, team: current_team, action: "app.https_enabled", target: @app)
        redirect_to dashboard_app_path(@app), notice: "HTTPS redirect enabled."
      end
    rescue ::Apps::Settings::Error => e
      redirect_to dashboard_app_path(@app), alert: "Failed: #{e.message}"
    end

    # Flip the Cloudflare proxy on the app's DNS record. Persists the
    # intended state immediately so the UI reflects the user's choice;
    # the actual CF API call happens in UpdateAppCdnJob which rolls
    # back the DB flag if the call fails.
    def toggle_cdn
      authorize @app, :update?
      toggle = ::Apps::Settings::CdnToggle.new(@app)
      if toggle.enabled?
        toggle.disable!
        Activity.log(user: current_user, team: current_team, action: "app.cdn_disabled", target: @app)
        redirect_to dashboard_app_path(@app), notice: "Cloudflare CDN turning off."
      else
        toggle.enable!
        Activity.log(user: current_user, team: current_team, action: "app.cdn_enabled", target: @app)
        redirect_to dashboard_app_path(@app), notice: "Cloudflare CDN turning on (DNS propagation may take a minute)."
      end
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

      target_email = params[:email].to_s
      begin
        transfer_record = ::Apps::Lifecycle::Transferrer.new(@app, from_user: current_user).call!(target_email)
        Activity.log(user: current_user, team: current_team, action: "app.transfer_requested",
                     target: @app, metadata: { from: current_user.email, to: transfer_record.to_user.email })
        redirect_to dashboard_app_path(@app), notice: "Transfer request sent to #{transfer_record.to_user.email}. Ownership will move once they accept."
      rescue ::Apps::Lifecycle::Error => e
        redirect_to dashboard_app_path(@app), alert: "Transfer failed: #{e.message}"
      end
    end

    # Danger Zone settings section — renders the type-to-confirm delete form
    # that posts to #destroy. Gated to team admins (same authz as the actual
    # destroy) so non-admins never see the delete affordance.
    def danger
      authorize @app, :destroy?
      render :danger
    end

    def toggle_maintenance
      authorize @app, :update?
      toggle = ::Apps::Settings::MaintenanceToggle.new(@app)
      if toggle.enabled?
        toggle.disable!
        Rails.cache.delete(maintenance_cache_key)
        Activity.log(user: current_user, team: current_team, action: "app.maintenance_disabled", target: @app)
        redirect_to dashboard_app_path(@app), notice: "Maintenance mode disabled."
      else
        toggle.enable!
        Rails.cache.delete(maintenance_cache_key)
        Activity.log(user: current_user, team: current_team, action: "app.maintenance_enabled", target: @app)
        redirect_to dashboard_app_path(@app), notice: "Maintenance mode enabled."
      end
    rescue ::Apps::Settings::Error => e
      redirect_to dashboard_app_path(@app), alert: "Failed: #{e.message}"
    end

    private

    # First-app onboarding + first-deploy waypoints. The apps list is the
    # post-login landing (/dashboard 301s here), so these live on #index.
    # Migrated 2026-06-07 from the retired Dashboard::DashboardController#show,
    # which the redirect had orphaned (tour + first_deploy event were dead).
    def run_onboarding_waypoints
      maybe_activate_onboarding!

      if (slug = flash[:deploy_template].presence) && TemplateRegistry.new.find(slug)
        redirect_to dashboard_template_path(slug, prefill: 1)
        return
      end

      if !session[:fds_sent] &&
         AppRecord.where(team: current_team).joins(:deploys)
                  .where(deploys: { status: :succeeded }).exists?
        flash.now[:posthog_event] = "first_deploy_succeeded"
        session[:fds_sent] = true
      end
    end

    # Deferred-section loaders (Deferrable). Each does only that section's
    # slow work; the shell #index renders instantly without them.
    def load_list
      @apps = policy_scope(AppRecord).main_apps
                .includes(:server, :team, :domains, dyno_allocations: :dyno_tier)
                .order(created_at: :desc).to_a
      @fleet = ::Apps::Fleet.for(@apps)
      counts = ::Apps::Fleet.counts(@fleet)
      @fleet_running = counts[:running].to_i
      @fleet_total = counts.values.sum
      @fleet_deploying = counts[:deploying].to_i
      @readouts = Organisms::AppsOverviewComponent.readouts_for(view_context, current_team)
      deploys = Deploy.in_progress_for(policy_scope(AppRecord).main_apps).to_a
      @track_deploy = deploys.first
      @track_more = [ deploys.size - 1, 0 ].max
      @sparks = ::Apps::CpuSparks.for(@apps)
      @last_deploys = Organisms::AppsRackComponent.last_deploys_for(@apps)
      @crashes = Organisms::AppsRackComponent.crashes_for(@apps)
    end

    def load_side
      scope = policy_scope(DatabaseService)
      @side_total = scope.count
      @side_databases = scope.order(:name).limit(Organisms::AppsSideComponent::MAX).to_a
      @side_sections = Organisms::AppsSideComponent.sections_for(view_context, current_team)
    end

    # Panel-section loaders. Re-scope from params[:app_id] (a query param on
    # the collection-level sections route, not the panel's own :id) rather
    # than reusing @app — the section request is a separate GET.
    def load_panel_deploys
      @panel_app = policy_scope(AppRecord).find(params[:app_id])
      @panel_releases = @panel_app.releases.includes(:deploy).order(version: :desc).limit(5)
    end

    def load_panel_logs
      @panel_app = policy_scope(AppRecord).find(params[:app_id])
      @panel_log_lines = recent_log_lines(@panel_app, limit: 8)
    end

    # Dashboard::LogsController#recent_log_lines is private there — not
    # shared across controllers, so replicate the fetch+split here rather
    # than reaching into another controller.
    def recent_log_lines(app, limit:)
      raw = ::Apps::LogReader.recent(app, lines: limit)
      return [] if raw.blank?
      raw.dup.force_encoding(Encoding::UTF_8).scrub("?").gsub(/\e\[[0-9;]*m/, "").split("\n").last(limit)
    rescue => e
      Rails.logger.warn "Failed to fetch panel logs for #{app.name}: #{e.message}"
      []
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

    # Maintenance cache key — busted by #toggle_maintenance so the UI flips
    # immediately. (The blocking fetch that read this on #show was removed:
    # the value was never rendered on the overview.)
    def maintenance_cache_key
      "app:#{@app.id}:maintenance_enabled"
    end
  end
end

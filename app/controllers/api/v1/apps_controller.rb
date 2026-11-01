module Api
  module V1
    class AppsController < BaseController
      include PlanEnforceable
      before_action :enforce_free_container_limit!, only: [ :create ]

      LIVE_COLUMNS = %w[live_cpu_pct live_mem_used_mb live_mem_limit_mb live_metrics_at].freeze

      def index
        apps = policy_scope(AppRecord)
        apps = apps.main_apps unless params[:include_previews].present?
        apps = apps.where("name ILIKE ?", "%#{params[:q]}%") if params[:q].present?
        apps = apps.select(:id, :name, :server_id, :team_id, :status, :is_preview, :pr_number, :parent_app_id, :created_at,
                           :live_cpu_pct, :live_mem_used_mb, :live_mem_limit_mb, :live_metrics_at).to_a
        stats = ::Apps::ListStats.for(apps)
        render json: apps.map { |app| app.as_json(except: LIVE_COLUMNS).merge(stats: stats[app.id]) }
      end

      def show
        app = find_app
        authorize app
        render json: app_json(app).merge(
          git_remote: app.git_remote_url,
          push_instructions: "git remote add wokku #{app.git_remote_url} && git push wokku #{app.deploy_branch || 'main'}",
          # wokkud host health — lets an agent distinguish "your app
          # crashed" from "the host is down; not your code".
          host_status: app.server&.heartbeat_status,
          host_heartbeat_at: app.server&.heartbeat_at
        )
      end

      def create
        server = Server.lookup!(params[:server_id])
        team = current_user.teams.first
        return render_api_error(:validation_failed, message: "User has no team") if team.nil?

        # Per-resource billing (spec 2026-09-24 §5.3): callers send a
        # `resources` hash (processes[web][...] shape) instead of box_size.
        builder_mode = Wokku.config.resource_builder? && params[:resources].present?

        # Bundle v2: read new params when feature flag is on.
        box_size = "sleeping"
        shared_engines = []
        if builder_mode
          box_size = nil
        elsif Addons::SharedProvisioner.feature_enabled?
          box_size = params[:box_size].presence || "sleeping"
          shared_engines = Array(params[:enabled_shared_engines])
          begin
            enforce_plan_quota!(current_user, size: box_size, additional: 1)
          rescue PlanEnforceable::PlanQuotaError => e
            render_api_error(:quota_exceeded, message: e.message, status: :payment_required)
            return
          end
        end

        app = server.app_records.build(
          name: params[:name],
          team: team,
          creator: current_user,
          deploy_branch: params[:deploy_branch] || "main",
          status: :created,
          box_size: box_size,
          enabled_shared_engines: shared_engines
        )
        # B6 W2: native apps are born without a dokku shell, fully flagged.
        if AppRecord.native_creates?
          app.assign_attributes(wokkud_native: true, wokkud_routed: true, wokkud_git: true, wokkud_lifecycle: true)
        end
        authorize app

        limit = Wokku.config.plan_enforcer.quota(current_user, :apps)
        if AppRecord.joins(team: :team_memberships).where(team_memberships: { user_id: current_user.id }).distinct.count >= limit
          render_api_error(:quota_exceeded, message: "App limit reached for your plan (#{limit})", status: :payment_required)
          return
        end

        app.save!

        warnings = []
        if builder_mode
          # Before DNS/provisioning: a refused size un-creates the app.
          result = Resources::ApplyChange.call(app: app, user: current_user, processes: params[:resources])
          unless result.ok
            app.destroy!
            return render_api_error(:invalid_params, message: result.error, status: :unprocessable_entity)
          end
        elsif Addons::SharedProvisioner.feature_enabled?
          # Bundle v2: create DynoAllocation from box_size mapping.
          tier_name = DynoTier::BOX_SIZE_TO_DYNO_TIER[box_size]
          chosen_tier = tier_name ? DynoTier.find_by(name: tier_name) : nil
          app.dyno_allocations.create!(process_type: "web", dyno_tier: chosen_tier, count: 1) if chosen_tier
        end

        # Create the DNS record in the canonical zone only — see comment on
        # Dashboard::AppsController#create.
        Wokku.config.dns_provider.create_app_record(app.name, server.host) rescue nil
        track("app.created", target: app)

        # Bundle v2: optional dedicated DB / Redis provisioning at create time.
        if Addons::SharedProvisioner.feature_enabled?
          dedicated_db_engine = params[:dedicated_db_engine].presence
          if dedicated_db_engine.present? && dedicated_db_engine.in?(%w[postgres mysql mongodb])
            begin
              DatabaseServiceUpgrade.call(app: app, user: current_user, engine: dedicated_db_engine)
            rescue UpgradeError => e
              warnings << "Dedicated #{dedicated_db_engine}: #{e.message}"
            end
          end

          if params[:add_dedicated_redis].present? && ActiveModel::Type::Boolean.new.cast(params[:add_dedicated_redis])
            begin
              DatabaseServiceUpgrade.call(app: app, user: current_user, engine: "redis")
            rescue UpgradeError => e
              warnings << "Dedicated redis: #{e.message}"
            end
          end
        end

        render json: app_json(app).merge(
          git_remote: app.git_remote_url,
          push_instructions: "git remote add wokku #{app.git_remote_url} && git push wokku #{app.deploy_branch || 'main'}",
          warnings: warnings.presence
        ).compact, status: :created
      end

      def update
        app = find_app
        authorize app

        # Name changes route through the same canonical service as #rename
        # (validation, host rename, bare-repo cleanup, DNS reshuffle).
        if params[:name].present? && params[:name] != app.name
          ::Apps::Lifecycle::Renamer.new(app).call!(params[:name].to_s)
        end
        app.update!(app_params)
        render json: app_json(app)
      rescue ::Apps::Lifecycle::Error => e
        render_api_error(ApiErrors.from_service_code(e.code), message: e.message)
      end

      def destroy
        app = find_app
        authorize app

        # Same canonical teardown as the dashboard's destroy — tears down a
        # flagged app's Swarm stack (Lifecycle::Ops.remove_if_flagged!),
        # removes DNS + the bare git repo, destroys the app row, and (a
        # deliberate behavior change from the old Dokku-only path) also
        # destroys any exclusively-linked database. ::-prefixed: no
        # Api::V1::Apps namespace exists today, but stay consistent with
        # the shadowing guard Task 1 established.
        # Async (AppDestroyJob): teardown outlives the proxy's ~30 s window.
        ::Apps::Destroyer.ensure_idle!(app)
        AppDestroyJob.perform_later(app.id)
        track("app.destroyed", target: app)
        render json: { message: "App deletion started", warnings: [] }, status: :accepted
      rescue ::Lifecycle::Ops::Busy
        render_api_error(:deploy_in_progress, message: "A deploy is in progress for this app; delete it once the deploy finishes")
      end

      def restart
        queue_process_action("restart")
      end

      def stop
        queue_process_action("stop")
      end

      def start
        queue_process_action("start")
      end

      def deploy
        app = find_app
        authorize app, :update?

        if ::Apps::Lifecycle::DeployLock.new(app).locked?
          return render_api_error(:app_locked, message: "App is locked; unlock first")
        end

        release = app.releases.create!(description: "Deploy via API")
        deploy = app.deploys.create!(release: release, status: :pending)
        DeployJob.perform_later(deploy.id)
        track("app.deployed", target: app)

        render json: { message: "Deploy triggered", deploy_id: deploy.id, release_id: release.id }, status: :accepted
      end

      # Async stack.run seam: 202 + run_id, polled via GET runs/:id
      # (RunsController#show) — since a migration can outlive kamal-proxy's
      # 30s response window.
      def run
        app = find_app
        authorize app, :update?
        run_async(app, params[:command].to_s)
      end

      # W7 Phase 2: raw dokku passthrough retired — the fleet is dokku-free.
      # Route stays so old CLIs get a typed 410 instead of a routing 404.
      def dokku
        app = find_app
        authorize app, :update?
        render_api_error(:passthrough_retired)
      end

      def github_connect
        app = find_app
        authorize app, :update?

        repo = params[:repo]
        branch = params[:branch] || "main"

        return render_api_error(:invalid_params, message: "repo is required", status: :unprocessable_entity) if repo.blank?

        app.update!(
          github_repo_full_name: repo,
          git_repository_url: "https://github.com/#{repo}.git",
          deploy_branch: branch,
          github_webhook_secret: app.github_webhook_secret || SecureRandom.hex(20)
        )

        render json: { message: "Connected to #{repo} (#{branch})", app_id: app.id, github_repo: repo, deploy_branch: branch }
      end

      def github_disconnect
        app = find_app
        authorize app, :update?

        app.update!(
          github_repo_full_name: nil,
          github_webhook_secret: nil
        )

        render json: { message: "GitHub disconnected" }
      end

      def metrics
        app = find_app
        authorize app, :show?
        render json: ::Api::V1::Serializers::AppMetrics.new(app).call
      end

      def monitor
        app = find_app
        authorize app, :show?
        render json: ::Api::V1::Serializers::AppMonitor.new(app).call
      end

      def vitals
        app = find_app
        authorize app, :show?
        render json: ::Api::V1::Serializers::AppVitals.new(app).call
      end

      # PR previews: on/off and which database each preview gets.
      def preview_settings
        app = find_app
        authorize app, :update?
        app.update!(params.permit(:preview_enabled, :database_strategy))
        render json: { preview_enabled: app.preview_enabled, database_strategy: app.database_strategy }
      end

      # New web-vitals ingest token; the old one stops working at once.
      def rotate_vitals_token
        app = find_app
        authorize app, :update?
        render json: { vitals_ingest_token: app.rotate_vitals_ingest_token! }
      end

      def rename
        app = find_app
        authorize app, :update?
        old_name = app.name
        new_app = ::Apps::Lifecycle::Renamer.new(app).call!(params[:name].to_s)
        Activity.log(user: current_user, team: app.team, action: "app.renamed", target: new_app,
                     metadata: { old_name: old_name, new_name: new_app.name })
        render json: { id: new_app.id, name: new_app.name }
      rescue ::Apps::Lifecycle::Error => e
        render_api_error(ApiErrors.from_service_code(e.code), message: e.message)
      end

      def clone
        app = find_app
        authorize app, :update?
        skip_deploy = params.key?(:skip_deploy) ? ActiveModel::Type::Boolean.new.cast(params[:skip_deploy]) : true
        new_app = ::Apps::Lifecycle::Cloner.new(app, user: current_user).call!(params[:name].to_s, skip_deploy: skip_deploy)
        Activity.log(user: current_user, team: app.team, action: "app.cloned", target: app,
                     metadata: { new_app_id: new_app.id, new_name: new_app.name })
        render json: { id: new_app.id, name: new_app.name }
      rescue ::Apps::Lifecycle::Error => e
        render_api_error(ApiErrors.from_service_code(e.code), message: e.message)
      end

      def lock
        app = find_app
        authorize app, :update?
        ::Apps::Lifecycle::DeployLock.new(app).lock!
        Activity.log(user: current_user, team: app.team, action: "app.locked", target: app)
        render json: { locked: true }
      rescue ::Apps::Lifecycle::Error => e
        render_api_error(ApiErrors.from_service_code(e.code), message: e.message)
      end

      def unlock
        app = find_app
        authorize app, :update?
        ::Apps::Lifecycle::DeployLock.new(app).unlock!
        Activity.log(user: current_user, team: app.team, action: "app.unlocked", target: app)
        render json: { locked: false }
      rescue ::Apps::Lifecycle::Error => e
        render_api_error(ApiErrors.from_service_code(e.code), message: e.message)
      end

      def transfer
        app = find_app
        authorize app, :destroy?
        transfer = ::Apps::Lifecycle::Transferrer.new(app, from_user: current_user).call!(params[:recipient_email].to_s)
        Activity.log(user: current_user, team: app.team, action: "app.transfer_requested", target: app,
                     metadata: { from: current_user.email, to: transfer.to_user.email })
        render json: { transfer_id: transfer.id, recipient_email: transfer.to_user.email, expires_at: transfer.expires_at }
      rescue ::Apps::Lifecycle::Error => e
        render_api_error(ApiErrors.from_service_code(e.code), message: e.message)
      end

      def set_https
        toggle_endpoint(::Apps::Settings::HttpsToggle, action_prefix: "app.https")
      end

      def set_cdn
        toggle_endpoint(::Apps::Settings::CdnToggle, action_prefix: "app.cdn")
      end

      def set_maintenance
        toggle_endpoint(::Apps::Settings::MaintenanceToggle, action_prefix: "app.maintenance")
      end

      private

      # Team-scoped lookup: another team's app is indistinguishable from a
      # missing one (404), never a 403 that confirms it exists.
      def find_app
        policy_scope(AppRecord).lookup!(params[:id])
      end

      # Raw model JSON minus the webhook secrets (never readable over the API).
      def app_json(app)
        app.as_json(except: %w[git_webhook_secret github_webhook_secret])
      end

      def run_async(app, command)
        return render_api_error(:invalid_params, message: "command required") if command.blank?

        op = ::Lifecycle::Ops.run!(app, command, wait: false)
        render json: { run_id: op.id }, status: :accepted
      rescue ::Lifecycle::Ops::Busy
        # The partial unique index on live lifecycle_ops (pending/claimed)
        # per app — another op already holds this app's lane. issue! converts
        # the RecordNotUnique into the typed Busy.
        render_api_error(:service_busy, message: "another operation is already in flight for this app")
      rescue ::Lifecycle::Ops::NotDeployed => e
        render_api_error(:invalid_params, message: e.message, status: :unprocessable_entity)
      end

      def toggle_endpoint(toggle_class, action_prefix:)
        app = find_app
        authorize app, :update?

        enabled = ActiveModel::Type::Boolean.new.cast(params[:enabled])
        return render_api_error(:invalid_params, message: "`enabled` must be true or false", status: :unprocessable_entity) if enabled.nil?

        toggle = toggle_class.new(app)
        if enabled
          toggle.enable!
          Activity.log(user: current_user, team: app.team, action: "#{action_prefix}_enabled", target: app)
        else
          toggle.disable!
          Activity.log(user: current_user, team: app.team, action: "#{action_prefix}_disabled", target: app)
        end

        render json: { enabled: enabled }
      rescue ::Apps::Settings::Error => e
        render_api_error(ApiErrors.from_service_code(e.code), message: e.message)
      end

      def app_params
        params.permit(:name, :deploy_branch)
      end

      # restart/stop/start are async — sync SSH calls were gateway-
      # timing-out at the proxy and corrupting Dokku state mid-flight
      # (see DokkuAppActionJob comments). 202 Accepted with an
      # action-queued message; clients can poll GET /apps/:id to see
      # status flip when the job completes.
      def queue_process_action(action)
        app = find_app
        authorize app
        if action != "stop" && !app.run_allowed?
          return render_api_error(:account_suspended, message: AppRecord::RUN_BLOCKED_MESSAGE)
        end
        app.update(pending_action: action)
        DokkuAppActionJob.perform_later(app.id, action)
        track("app.#{action}_queued", target: app)
        render json: { message: "#{action.capitalize} queued", app_id: app.id, action: action }, status: :accepted
      end
    end
  end
end

module Dashboard
  class DatabasesController < BaseController
    include PlanEnforceable
    before_action :reject_creation_during_deletion_pending, only: [ :create ]
    before_action :enforce_free_database_limit!, only: [ :create ]

    def index
      @databases = policy_scope(DatabaseService).includes(:server, :app_records).order(:service_type, :name)
      # Surface orphans (addons with no app_records) separately so users
      # notice when CreateAddonJob died mid-link or unlink left a stray
      # addon — otherwise these only show up under "By app → Unlinked".
      @orphan_addons = @databases.reject { |db| db.app_records.any? }
      @by_type = @databases.group_by(&:service_type)
      @by_app = @databases.group_by { |db| db.app_records.map(&:name).join(", ").presence || "Unlinked" }
      @database = DatabaseService.new
      @apps = policy_scope(AppRecord).includes(:server).order(:name)
      @group_by = params[:group] || "type"
      # shared_free is offered for postgres only — the underlying
      # dokku-shared-postgres plugin (v0.2.1, smoke-passed 2026-05-13)
      # provisions a logical tenant inside a per-server shared host
      # container. Listed alongside paid tiers so users see "Free"
      # as a first-class plan, not a hidden option.
      @tiers_by_type = ServiceTier.available
                                  .order(:monthly_price_cents)
                                  .group_by(&:service_type)
    end

    def show
      @database = DatabaseService.lookup!(params[:id])
      authorize @database
      @info = policy(@database).update? ? fetch_info : {}
      @linked_apps = @database.app_records
      # Scope the "Connect an app" picker to the user's own apps —
      # `@database.server.app_records` returns every app on that
      # server, including other tenants', which leaks names. Use
      # policy_scope so admins still see everything but regular users
      # only see their own.
      @available_apps = policy_scope(AppRecord)
                          .where(server_id: @database.server_id)
                          .where.not(id: @linked_apps.pluck(:id))
                          .order(:name)
      @available_tiers = ServiceTier.for_type(@database.service_type).available
                                   .where.not(name: "shared_free")
                                   .order(:price_cents_per_hour)
      @current_tier = @database.service_tier
      @usage = fetch_usage
    end

    def settings
      @database = DatabaseService.lookup!(params[:id])
      authorize @database, :show?
      @linked_apps = @database.app_records
      @available_apps = policy_scope(AppRecord)
                          .where(server_id: @database.server_id)
                          .where.not(id: @linked_apps.pluck(:id))
                          .order(:name)
      @current_tier = @database.service_tier
    end

    def new
      # The standalone /new page has been folded into the index slide-panel
      # so we have one source of truth for the form. Redirect anyone landing
      # here from a stale link.
      redirect_to dashboard_addons_path
    end

    def create
      # Add-ons attach to an app; server is derived from the app. This
      # mirrors Heroku where add-ons live on an app's Resources tab and
      # the underlying infra is opaque to end users.
      app = policy_scope(AppRecord).find(params[:database_service][:app_id])
      server = app.server

      # Bundle v2 (backlog 2.8) — unified picker posts `mode=shared|dedicated`.
      # Shared mode bypasses the create-row-then-async-job flow entirely
      # and routes through Addons::SharedProvisioner, which is idempotent
      # and synchronous (logical tenant on the host container).
      mode = (params[:mode] || params[:database_service][:tier_name]).to_s.presence
      if mode == "shared"
        engine = params[:database_service][:service_type].to_s
        result = Addons::SharedProvisioner.new(app: app, engine: engine).call
        case result
        when :provisioned
          track("database.shared_attached", target: app, metadata: { engine: engine })
          redirect_to dashboard_app_resources_path(app), notice: "Shared #{engine} attached to #{app.name}." and return
        when :already_attached
          redirect_to dashboard_app_resources_path(app), notice: "Shared #{engine} is already attached." and return
        when :feature_disabled
          redirect_to dashboard_addons_path, alert: "Shared engines are not enabled on this install." and return
        else
          redirect_to dashboard_addons_path, alert: "Couldn't attach shared #{engine}: #{result.inspect}." and return
        end
      end

      attrs = database_params.except(:app_id).merge(server: server, status: :creating, creator: current_user)
      attrs[:tier_name] = "basic" if attrs[:tier_name].blank?

      # Per-resource billing (spec 2026-09-24 §5.3): the builder's dedicated
      # panel posts bare cpu/memory_mb/disk_gb (ResourceBuilderComponent
      # name: "") instead of picking a tier. Same enforcer + capacity checks
      # ResizeService runs, via the shared Resources::ApplyChange helper.
      if mode == "dedicated" && Wokku.config.resource_builder? && params[:cpu].present?
        shape = Resources::Shape.new(cpu: params[:cpu], memory_mb: params[:memory_mb], disk_gb: params[:disk_gb])
        engine = attrs[:service_type]
        unless shape.valid?(engine: engine)
          redirect_to dashboard_addons_path, alert: shape.errors(engine: engine).join(", ")
          return
        end
        check = Resources::ApplyChange.check_new_shape(team: app.team, server: server, shape: shape)
        unless check.ok
          redirect_to dashboard_addons_path, alert: check.error
          return
        end
        attrs.merge!(cpu: shape.cpu, memory_mb: shape.memory_mb, disk_gb: shape.disk_gb)
      end

      # Stuck error/creating rows from a prior failed attempt hold the
      # unique (server_id, name) slot and block retries with a useless
      # "name already taken". Sweep them before saving — the row never
      # made it past provisioning, so there's nothing to preserve.
      if attrs[:name].present?
        DatabaseService.where(server: server, name: attrs[:name], status: [ :error, :creating ])
                       .where("created_at < ?", 5.minutes.ago)
                       .destroy_all
      end

      @database = DatabaseService.new(attrs)
      authorize @database

      unless @database.save
        redirect_to dashboard_addons_path, alert: "Couldn't create add-on: #{@database.errors.full_messages.to_sentence.presence || 'invalid input'}."
        return
      end

      # Provisioning happens async — the agent may need to pull a multi-MB
      # docker image, which can blow past kamal-proxy's 30s response
      # timeout. The DB row stays in status=:creating; CreateAddonJob
      # flips it to :running on success or marks it :error on failure.
      CreateAddonJob.perform_later(@database.id, app.id)
      track("database.create_queued", target: @database, metadata: { tier: @database.tier_name, app: app.name })

      # Send the user back to the app's resources page rather than the
      # addon's show page. Linking happens async via CreateAddonJob, so
      # the addon has no app_records yet — DatabaseServicePolicy#show?
      # requires that link and would 403 here. Resources page also
      # gives them context (they just added an addon to this app).
      redirect_to dashboard_app_resources_path(app),
        notice: "#{@database.service_type.capitalize} #{@database.name} is provisioning — this can take a minute or two for image pulls."
    rescue ActiveRecord::RecordNotFound
      redirect_to dashboard_addons_path, alert: "Pick an app first."
    rescue => e
      @database&.update(status: :error)
      redirect_to dashboard_addons_path, alert: "Failed to create add-on: #{e.message}"
    end

    def destroy
      @database = DatabaseService.find(params[:id])
      authorize @database

      # DatabaseProvisioner.destroy! takes the farewell snapshot, tears down
      # the underlying service (dokku or wokkud, dedicated or shared), and
      # destroys the row — which cascades app_databases (dependent: :destroy),
      # so linked apps are unlinked for free without a separate unlink pass.
      DatabaseProvisioner.destroy!(database_service: @database)
      track("database.destroyed", target: @database)
      redirect_to dashboard_addons_path, notice: "Database #{@database.name} destroyed."
    rescue => e
      redirect_to dashboard_addons_path, alert: "Failed to destroy database: #{e.message}"
    end

    # Re-enqueue CreateAddonJob for an errored addon. The job is
    # idempotent on the link side (find_or_create_by! + EnvWriter upsert);
    # the agent's service.create handles an existing container. Common
    # case: a transient agent outage, or an unsupported engine picked by
    # mistake and the user retries after switching apps.
    def retry
      @database = DatabaseService.lookup!(params[:id])
      authorize @database, :update?
      app = @database.app_records.first || @database.creator&.app_records&.first
      unless app
        return redirect_to dashboard_addon_path(@database), alert: "Pick an app to attach to first."
      end
      @database.update!(status: :creating, last_error: nil)
      CreateAddonJob.perform_later(@database.id, app.id)
      redirect_to dashboard_addon_path(@database), notice: "Retrying provisioning…"
    end

    # Heroku-style "Change Tier" button. Updates tier_name in the DB and
    # queues ApplyDatabaseTierJob to push the new memory / max_connections
    # to the running container. Brief restart for connection-cap changes.
    def change_tier
      @database = DatabaseService.lookup!(params[:id])
      authorize @database, :update?

      if @database.shared?
        redirect_to dashboard_addon_path(@database), alert: "Free shared databases can't change tier — upgrade to a dedicated database first."
        return
      end

      # Builder mode: resize goes through Resources::ResizeService (limit +
      # capacity checks) — a legacy tier change would bypass them.
      if Wokku.config.resource_builder?
        return redirect_to dashboard_addon_path(@database), alert: "Tiers are retired — use the resource builder to resize this database."
      end

      tier = ServiceTier.find_by!(service_type: @database.service_type, name: params[:tier_name])
      @database.update!(tier_name: tier.name)
      ApplyDatabaseTierJob.perform_later(@database.id)
      track("database.tier_changed", target: @database, metadata: { tier: tier.name })

      redirect_to dashboard_addon_path(@database), notice: "Tier change to #{tier.name} queued. Brief restart in progress."
    rescue ActiveRecord::RecordNotFound
      redirect_to dashboard_addon_path(@database), alert: "Tier not available."
    rescue StandardError => e
      redirect_to dashboard_addon_path(@database), alert: "Tier change failed: #{e.message}"
    end

    def resize
      db = DatabaseService.find(params[:id])
      authorize db, :resize?
      shape = Resources::Shape.new(cpu: params[:cpu], memory_mb: params[:memory_mb], disk_gb: params[:disk_gb])
      result = Resources::ResizeService.call(db: db, user: current_user, shape: shape)
      redirect_to dashboard_addon_path(db), **(result.ok ? { notice: "Resizing #{db.name}…" } : { alert: result.error })
    end

    def link
      @database = DatabaseService.find(params[:id])
      authorize @database
      # Scope app lookup to the user's own apps — `@database.server`
      # has every tenant's apps. Same leak we fixed on the show page.
      app = policy_scope(AppRecord).where(server_id: @database.server_id).find(params[:app_id])
      authorize app, :update? # writes the app's env + restarts it — viewers can't

      # W7 Phase 2: linking is a control-plane write, not a dokku command —
      # an AppDatabase row plus an EnvWriter env write, exactly the stanza
      # DatabaseProvisioner#provision_dedicated_via_ops! uses. Alias naming
      # mirrors the provisioner: "DATABASE" for shared tenants (DATABASE_URL),
      # <SERVICE_TYPE> for dedicated (POSTGRES_URL / REDIS_URL / ...).
      link_row = @database.app_databases.find_or_create_by!(app_record: app) do |ad|
        ad.alias_name = @database.shared? ? "DATABASE" : @database.service_type.upcase
      end
      ::Apps::EnvWriter.set(app, { "#{link_row.alias_name}_URL" => @database.dsn }) if @database.dsn.present?
      # dokku's `<plugin>:link` restarted the app so the new env took
      # effect — converge (restart: true) is the wokkud equivalent.
      restart_for_env(app)

      redirect_to dashboard_addon_path(@database), notice: "Linked #{app.name} to #{@database.name}."
    rescue ActiveRecord::RecordNotFound, Pundit::NotAuthorizedError
      raise # ApplicationController renders 404 / not-authorized, not the generic alert
    rescue => e
      redirect_to dashboard_addon_path(@database), alert: "Link failed: #{e.message}"
    end

    def unlink
      @database = DatabaseService.find(params[:id])
      authorize @database
      app = policy_scope(AppRecord).where(id: @database.app_records.select(:id)).find(params[:app_id])
      authorize app, :update? # unsets the app's env + restarts it — viewers can't

      # W7 Phase 2: mirror of #link — unset the alias'd URL env var (same
      # naming DatabaseProvisioner's destroy path unsets) and drop the row.
      link_row = @database.app_databases.find_by(app_record: app)
      if link_row
        ::Apps::EnvWriter.unset(app, "#{link_row.alias_name}_URL")
        link_row.destroy
      end
      restart_for_env(app)

      redirect_to dashboard_addon_path(@database), notice: "Unlinked #{app.name} from #{@database.name}."
    rescue ActiveRecord::RecordNotFound, Pundit::NotAuthorizedError
      raise # ApplicationController renders 404 / not-authorized, not the generic alert
    rescue => e
      redirect_to dashboard_addon_path(@database), alert: "Unlink failed: #{e.message}"
    end

    private

    def database_params
      params.require(:database_service).permit(:name, :service_type, :tier_name, :app_id)
    end

    # W7 Phase 2: connection info comes from the control plane — the row's
    # encrypted DSN is the single connection truth (usage metrics come from
    # fetch_usage's live_* columns). The old dokku `<plugin>:info` keys the
    # panel no longer receives: config_dir, data_dir, exposed_ports, id,
    # internal_ip, links, post_*_network, service_root, status, version.
    def fetch_info
      { "dsn" => @database.dsn }.compact_blank
    rescue => e
      # Legacy rows can fail DSN decryption — degrade to an empty panel.
      Rails.logger.warn "Failed to fetch database info for #{@database.name}: #{e.message}"
      {}
    end

    # Best-effort: the link/unlink itself is already committed; a failed
    # restart shouldn't turn a successful link into an alert.
    def restart_for_env(app)
      ::Apps::Restarter.restart(app)
    rescue => e
      Rails.logger.warn "Restart after link change failed for #{app.name}: #{e.message}"
    end

    # Read pre-collected metrics from MetricsPollJob's most recent run.
    # No SSH at render time — the page is fast and scales independently
    # of user / page-view count.
    def fetch_usage
      return {} if @database.shared?
      ram_mb = @database.live_mem_used_mb
      {
        db_bytes:     @database.live_db_bytes,
        ram_bytes:    ram_mb ? ram_mb * 1.megabyte : nil,
        collected_at: @database.live_metrics_at,
        stale:        @database.live_metrics_at.nil? || @database.live_metrics_at < 5.minutes.ago
      }
    end
  end
end

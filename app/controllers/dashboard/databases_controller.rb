module Dashboard
  class DatabasesController < BaseController
    include PlanEnforceable
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
      @tiers_by_type = ServiceTier.available.where.not(name: "shared_free")
                                  .order(:monthly_price_cents)
                                  .group_by(&:service_type)
    end

    def show
      @database = DatabaseService.lookup!(params[:id])
      authorize @database
      @info = fetch_info
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
      attrs = database_params.except(:app_id).merge(server: server, status: :creating, creator: current_user)
      attrs[:tier_name] = "basic" if attrs[:tier_name].blank?

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

      # Provisioning happens async — Dokku may need to pull a multi-MB
      # docker image (memcached/elasticsearch/etc.), which can blow past
      # kamal-proxy's 30s response timeout. The DB row stays in
      # status=:creating; CreateAddonJob flips it to :running on success
      # or destroys the row on failure.
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

      client = Dokku::Client.new(@database.server)

      # Dokku refuses to destroy a service while any app is still
      # linked to it ("Cannot delete linked service"). Unlink from
      # every linked app first. Tolerate already-unlinked errors so a
      # half-completed previous attempt doesn't block.
      @database.app_records.each do |app|
        Dokku::Databases.new(client).unlink(@database.service_type, @database.name, app.name)
      rescue Dokku::Client::CommandError => e
        raise unless e.message.match?(/not linked|no link|does not exist/i)
        Rails.logger.info("Unlink #{app.name} ↔ #{@database.name} already gone — continuing.")
      end

      Dokku::Databases.new(client).destroy(@database.service_type, @database.name)
      @database.destroy
      track("database.destroyed", target: @database)
      redirect_to dashboard_addons_path, notice: "Database #{@database.name} destroyed."
    rescue => e
      redirect_to dashboard_addons_path, alert: "Failed to destroy database: #{e.message}"
    end

    # Re-enqueue CreateAddonJob for an errored addon. The job is
    # idempotent on the create side (postgres:create returns "Service
    # already exists" which we treat as success via the rescue path)
    # and on the link side (find_or_create_by). Common case: a
    # transient SSH timeout, or the underlying Dokku app didn't exist
    # at first attempt and now does (e.g. user pushed code in between).
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

    def link
      @database = DatabaseService.find(params[:id])
      authorize @database
      # Scope app lookup to the user's own apps — `@database.server`
      # has every tenant's apps. Same leak we fixed on the show page.
      app = policy_scope(AppRecord).where(server_id: @database.server_id).find(params[:app_id])

      client = Dokku::Client.new(@database.server)

      # Idempotent on the Dokku side: if `<plugin>:link` errors with
      # "already linked", treat it as success and let the AppDatabase
      # row creation finish so our DB matches Dokku's reality. Without
      # this, a failed first attempt (e.g. missing alias) blocks the
      # retry — Dokku says "already linked", we surface a confusing
      # error, and the user is stuck.
      begin
        Dokku::Databases.new(client).link(@database.service_type, @database.name, app.name)
      rescue Dokku::Client::CommandError => e
        raise unless e.message.match?(/already linked|exists/i)
        Rails.logger.info("Link to #{app.name} already exists on Dokku — reconciling DB row.")
      end

      # `alias_name` is required (validation) and surfaces in DATABASE_URL
      # config var prefixes for multi-DB apps. Default to <SERVICE_TYPE>
      # so the user gets the standard `DATABASE_URL` / `REDIS_URL` shape.
      @database.app_databases.find_or_create_by!(app_record: app) do |ad|
        ad.alias_name = @database.service_type.upcase
      end

      redirect_to dashboard_addon_path(@database), notice: "Linked #{app.name} to #{@database.name}."
    rescue => e
      redirect_to dashboard_addon_path(@database), alert: "Link failed: #{e.message}"
    end

    def unlink
      @database = DatabaseService.find(params[:id])
      authorize @database
      app = @database.app_records.find(params[:app_id])

      client = Dokku::Client.new(@database.server)
      # Idempotent: if Dokku's already unlinked (e.g. previous attempt
      # half-succeeded, or someone unlinked via SSH), let the local
      # cleanup finish so we don't leave a dangling AppDatabase row.
      begin
        Dokku::Databases.new(client).unlink(@database.service_type, @database.name, app.name)
      rescue Dokku::Client::CommandError => e
        raise unless e.message.match?(/not linked|no link|does not exist/i)
        Rails.logger.info("Unlink for #{app.name} already gone on Dokku — reconciling DB row.")
      end
      @database.app_databases.find_by(app_record: app)&.destroy

      redirect_to dashboard_addon_path(@database), notice: "Unlinked #{app.name} from #{@database.name}."
    rescue => e
      redirect_to dashboard_addon_path(@database), alert: "Unlink failed: #{e.message}"
    end

    private

    def database_params
      params.require(:database_service).permit(:name, :service_type, :tier_name, :app_id)
    end

    # Translate Dokku CommandError stderr into something a user can act on.
    # The plugin-not-installed message in particular is unfriendly raw.
    def friendly_dokku_error(message, service_type)
      if message.to_s.match?(/is not a dokku command|plugin .* does not exist/i)
        "#{service_type.capitalize} isn't available on this server yet. Pick a different add-on type or ask an admin to install the plugin."
      else
        "Couldn't create add-on: #{message.to_s.lines.first&.strip}"
      end
    end

    def fetch_info
      client = Dokku::Client.new(@database.server)
      Dokku::Databases.new(client).info(@database.service_type, @database.name)
    rescue => e
      Rails.logger.warn "Failed to fetch database info for #{@database.name}: #{e.message}"
      {}
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

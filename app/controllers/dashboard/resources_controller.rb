module Dashboard
  class ResourcesController < BaseController
    include PlanEnforceable

    before_action :set_app

    def show
      authorize @app, :show?
      return render_deferred_fragment if params[:deferred]

      # Shell branch: only cheap DB assigns (no SSH).
      @addons = @app.database_services.includes(:server, :app_records)
      @available_types = addon_types
    end

    def create
      authorize @app, :update?

      service_type = params[:service_type] || params.dig(:database_service, :service_type)
      # Bundle v2 (backlog 2.8) — picker posts `mode=shared|dedicated`.
      # Legacy `tier` param honored as a fallback so older bookmarks
      # don't 500 mid-deploy. Defaults to shared since every paid plan
      # gets it free.
      mode = (params[:mode] || params[:tier]).to_s.presence || "shared"
      tier = mode == "shared" ? DatabaseProvisioner::SHARED_TIER : DatabaseProvisioner::DEFAULT_TIER

      # Per-resource billing (spec 2026-09-24 §5.3): a dedicated create from
      # the slider builder posts bare cpu/memory_mb/disk_gb (ResourceBuilderComponent
      # name: "") instead of picking a fixed tier. Same enforcer + capacity
      # checks ResizeService runs, via the shared Resources::ApplyChange helper.
      shape = nil
      if mode == "dedicated" && Wokku.config.resource_builder? && params[:cpu].present?
        shape = Resources::Shape.new(cpu: params[:cpu], memory_mb: params[:memory_mb], disk_gb: params[:disk_gb])
        return redirect_to dashboard_app_resources_path(@app), alert: shape.errors.join(", ") unless shape.valid?
        check = Resources::ApplyChange.check_new_shape(team: @app.team, server: @app.server, shape: shape)
        return redirect_to dashboard_app_resources_path(@app), alert: check.error unless check.ok
      end

      db = DatabaseProvisioner.new(
        app: @app,
        service_type: service_type,
        tier: tier,
        name: params[:addon_name].presence || params.dig(:database_service, :name).presence,
        creator: current_user,
        shape: shape
      ).call

      track("addon.created", target: db)
      notice = mode == "shared" ? "Shared #{service_type} added and linked." : "Dedicated #{addon_label(service_type)} added and linked."
      redirect_to dashboard_app_resources_path(@app), notice: notice
    rescue => e
      redirect_to dashboard_app_resources_path(@app), alert: "Failed to add #{service_type}: #{e.message}"
    end

    def update
      authorize @app, :update?
      result = Resources::ApplyChange.call(
        app: @app, user: current_user,
        processes: params[:processes].respond_to?(:to_unsafe_h) ? params[:processes].to_unsafe_h : (params[:processes] || {}),
        volume_disk_gb: params[:volume_disk_gb].presence
      )
      if result.ok
        redirect_to dashboard_app_resources_path(@app), notice: t("resources.applying", default: "Applying new size — containers restart.")
      else
        redirect_to dashboard_app_resources_path(@app), alert: result.error
      end
    end

    def destroy
      authorize @app, :update?

      db = DatabaseService.find(params[:addon_id])

      DatabaseProvisioner.destroy!(database_service: db)
      track("addon.destroyed", target: db)

      redirect_to dashboard_app_resources_path(@app), notice: "#{db.name} removed."
    rescue => e
      redirect_to dashboard_app_resources_path(@app), alert: "Failed to remove add-on: #{e.message}"
    end

    private

    def render_deferred_fragment
      # Dyno scaling content was on /scaling — merged here so a single
      # Resources tab shows compute + add-ons + cost (Heroku model).
      sync_process_scales_safely
      @process_scales = @app.process_scales.order(:process_type)
      @allocations = @app.dyno_allocations.includes(:dyno_tier).order(:process_type)
      @scales = @app.process_scales.pluck(:process_type, :count).to_h
      @dyno_tiers = defined?(DynoTier) ? DynoTier.available.order(:memory_mb) : []
      @current_allocation = defined?(DynoAllocation) ? @app.dyno_allocations.includes(:dyno_tier).find_by(process_type: "web") : nil
      # Per-size headroom (base plan quota + active purchased addons − current usage),
      # so the resize card shows "Resize" when the user can move into a size for free
      # and "Buy" only when they're actually out of that size.
      @box_size_headroom = DynoTier::DYNO_TIER_TO_BOX_SIZE.values.uniq.index_with do |size|
        quota_allowed(current_user, size) - current_box_count(current_user, size)
      end
      render partial: "dashboard/resources/frame", layout: false
    end

    def set_app
      @app = AppRecord.find(params[:app_id])
    end

    def addon_types
      [
        # Databases
        { type: "postgres", tier: "shared_free", label: "PostgreSQL — Free (Shared)", category: "Databases", description: "150 MB, 5 connections, shared cluster — free tier" },
        { type: "postgres", label: "PostgreSQL", category: "Databases", description: "Reliable and powerful relational database" },
        { type: "mysql", label: "MySQL", category: "Databases", description: "Popular open source relational database" },
        { type: "mongodb", label: "MongoDB", category: "Databases", description: "Document database for modern apps" },
        { type: "clickhouse", label: "ClickHouse", category: "Databases", description: "Column-oriented analytics database" },
        # Caching
        { type: "redis", label: "Redis", category: "Caching", description: "In-memory data store and cache" },
        { type: "memcached", label: "Memcached", category: "Caching", description: "High-performance memory cache" },
        # Search
        { type: "elasticsearch", label: "Elasticsearch", category: "Search", description: "Full-text search and analytics engine" },
        { type: "meilisearch", label: "Meilisearch", category: "Search", description: "Fast, typo-tolerant search engine" },
        # Messaging
        { type: "rabbitmq", label: "RabbitMQ", category: "Messaging", description: "Message broker for async processing" },
        { type: "nats", label: "NATS", category: "Messaging", description: "High-performance message streaming" }
      ]
    end

    def addon_label(type)
      addon_types.find { |a| a[:type] == type }&.dig(:label) || type.capitalize
    end

    def sync_process_scales_safely
      # Reads Swarm task state fanned out from the heartbeat
      # (app_records.live_containers) — no SSH.
      # ponytail: count every task per process type, mirroring the legacy
      # "count each status_<type>_<n> entry" semantics.
      types =
        Array(@app.live_containers).each_with_object(Hash.new(0)) do |c, h|
          pt = c["process"]
          h[pt] += 1 if pt.present?
        end
      types.each do |t, count|
        ps = @app.process_scales.find_or_initialize_by(process_type: t)
        ps.update!(count: count) if ps.new_record?
      end
    rescue StandardError => e
      Rails.logger.warn "ResourcesController: scale sync skipped for #{@app.name}: #{e.message}"
    end
  end
end

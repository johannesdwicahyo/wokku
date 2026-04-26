module Dashboard
  class ResourcesController < BaseController
    before_action :set_app

    def show
      authorize @app, :show?
      @addons = @app.database_services.includes(:server)
      @available_types = addon_types

      # Dyno scaling content was on /scaling — merged here so a single
      # Resources tab shows compute + add-ons + cost (Heroku model).
      sync_process_scales_safely
      @process_scales = @app.process_scales.order(:process_type)
      @dyno_tiers = defined?(DynoTier) ? DynoTier.available.order(:memory_mb) : []
      @current_allocation = defined?(DynoAllocation) ? @app.dyno_allocations.includes(:dyno_tier).find_by(process_type: "web") : nil
    end

    def create
      authorize @app, :update?

      service_type = params[:service_type]
      tier = params[:tier].presence || DatabaseProvisioner::DEFAULT_TIER

      db = DatabaseProvisioner.new(
        app: @app,
        service_type: service_type,
        tier: tier,
        name: params[:addon_name].presence
      ).call

      track("addon.created", target: db)
      notice = tier == DatabaseProvisioner::SHARED_TIER ? "Free shared Postgres added and linked." : "#{addon_label(service_type)} added and linked."
      redirect_to dashboard_app_resources_path(@app), notice: notice
    rescue => e
      redirect_to dashboard_app_resources_path(@app), alert: "Failed to add #{service_type}: #{e.message}"
    end

    def destroy
      authorize @app, :update?

      db = DatabaseService.find(params[:addon_id])
      client = Dokku::Client.new(@app.server)

      # Dedicated DBs need an explicit unlink; shared DBs are attached only via
      # DATABASE_URL config and are torn down by DatabaseProvisioner.destroy!
      unless db.shared?
        begin
          Dokku::Databases.new(client).unlink(db.service_type, db.name, @app.name)
        rescue => e
          Rails.logger.warn "Unlink failed (may already be unlinked): #{e.message}"
        end
      end

      DatabaseProvisioner.destroy!(database_service: db, client: client)
      track("addon.destroyed", target: db)

      redirect_to dashboard_app_resources_path(@app), notice: "#{db.name} removed."
    rescue => e
      redirect_to dashboard_app_resources_path(@app), alert: "Failed to remove add-on: #{e.message}"
    end

    private

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
      return unless defined?(Dokku::Processes)
      client = Dokku::Client.new(@app.server)
      report = Dokku::Processes.new(client).list(@app.name)
      types = {}
      report.each do |k, _v|
        if k.match?(/status_\w+_\d+/)
          t = k.split("_")[1]
          types[t] = (types[t] || 0) + 1
        end
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

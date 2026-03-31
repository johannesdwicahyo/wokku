module Dashboard
  class ResourcesController < BaseController
    before_action :set_app

    def show
      authorize @app, :show?
      @addons = @app.database_services.includes(:server)
      @available_types = addon_types
    end

    def create
      authorize @app, :update?

      service_type = params[:service_type]
      name = params[:addon_name].presence || "#{@app.name}-#{service_type}"

      server = @app.server
      client = Dokku::Client.new(server)

      db = DatabaseService.create!(
        name: name,
        service_type: service_type,
        server: server,
        status: :creating
      )

      Dokku::Databases.new(client).create(service_type, name)
      Dokku::Databases.new(client).link(service_type, name, @app.name)
      db.update!(status: :running)
      @app.app_databases.create!(database_service: db, alias_name: service_type.upcase)

      track("addon.created", target: db)
      redirect_to dashboard_app_resources_path(@app), notice: "#{addon_label(service_type)} added and linked."
    rescue => e
      db&.update(status: :error)
      redirect_to dashboard_app_resources_path(@app), alert: "Failed to add #{service_type}: #{e.message}"
    end

    def destroy
      authorize @app, :update?

      db = DatabaseService.find(params[:addon_id])
      client = Dokku::Client.new(@app.server)

      begin
        Dokku::Databases.new(client).unlink(db.service_type, db.name, @app.name)
      rescue => e
        Rails.logger.warn "Unlink failed (may already be unlinked): #{e.message}"
      end

      Dokku::Databases.new(client).destroy(db.service_type, db.name)
      db.destroy
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
        { type: "postgres", label: "Heroku Postgres", icon: "database", description: "Reliable and powerful database", color: "blue" },
        { type: "mysql", label: "MySQL", icon: "database", description: "Popular open source database", color: "orange" },
        { type: "mariadb", label: "MariaDB", icon: "database", description: "MySQL-compatible database", color: "sky" },
        { type: "mongodb", label: "MongoDB", icon: "database", description: "Document database for modern apps", color: "green" },
        { type: "redis", label: "Redis", icon: "zap", description: "In-memory data store and cache", color: "red" },
        { type: "memcached", label: "Memcached", icon: "zap", description: "High-performance memory cache", color: "gray" },
        { type: "rabbitmq", label: "RabbitMQ", icon: "message", description: "Message broker for async processing", color: "orange" },
        { type: "elasticsearch", label: "Elasticsearch", icon: "search", description: "Full-text search and analytics", color: "yellow" }
      ]
    end

    def addon_label(type)
      addon_types.find { |a| a[:type] == type }&.dig(:label) || type.capitalize
    end
  end
end

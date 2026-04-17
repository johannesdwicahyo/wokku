module Dashboard
  class DatabasesController < BaseController
    include PlanEnforceable
    before_action :enforce_free_database_limit!, only: [ :create ]

    def index
      @databases = policy_scope(DatabaseService).includes(:server, :app_records).order(:service_type, :name)
      @by_type = @databases.group_by(&:service_type)
      @by_app = @databases.group_by { |db| db.app_records.map(&:name).join(", ").presence || "Unlinked" }
      @database = DatabaseService.new
      @servers = policy_scope(Server)
      @group_by = params[:group] || "type"
    end

    def show
      @database = DatabaseService.find(params[:id])
      authorize @database
      @info = fetch_info
      @linked_apps = @database.app_records
      @available_apps = @database.server.app_records.where.not(id: @linked_apps.pluck(:id))
    end

    def new
      @database = DatabaseService.new
      @servers = policy_scope(Server)
    end

    def create
      server = policy_scope(Server).find(params[:database_service][:server_id])
      @database = DatabaseService.new(database_params.merge(server: server, status: :creating))
      authorize @database

      if @database.save
        # Create on Dokku server
        client = Dokku::Client.new(server)
        Dokku::Databases.new(client).create(@database.service_type, @database.name)
        @database.update!(status: :running)
        track("database.created", target: @database)
        redirect_to dashboard_resource_path(@database), notice: "Database #{@database.name} created."
      else
        @servers = policy_scope(Server)
        @databases = policy_scope(DatabaseService).includes(:server)
        render :index, status: :unprocessable_entity
      end
    rescue => e
      @database&.update(status: :error)
      redirect_to dashboard_resources_path, alert: "Failed to create database: #{e.message}"
    end

    def destroy
      @database = DatabaseService.find(params[:id])
      authorize @database

      # Destroy on Dokku server
      client = Dokku::Client.new(@database.server)
      Dokku::Databases.new(client).destroy(@database.service_type, @database.name)
      @database.destroy
      track("database.destroyed", target: @database)
      redirect_to dashboard_resources_path, notice: "Database #{@database.name} destroyed."
    rescue => e
      redirect_to dashboard_resources_path, alert: "Failed to destroy database: #{e.message}"
    end

    def link
      @database = DatabaseService.find(params[:id])
      authorize @database
      app = @database.server.app_records.find(params[:app_id])

      client = Dokku::Client.new(@database.server)
      Dokku::Databases.new(client).link(@database.service_type, @database.name, app.name)
      @database.app_databases.create!(app_record: app)

      redirect_to dashboard_resource_path(@database), notice: "Linked #{app.name} to #{@database.name}."
    rescue => e
      redirect_to dashboard_resource_path(@database), alert: "Link failed: #{e.message}"
    end

    def unlink
      @database = DatabaseService.find(params[:id])
      authorize @database
      app = @database.app_records.find(params[:app_id])

      client = Dokku::Client.new(@database.server)
      Dokku::Databases.new(client).unlink(@database.service_type, @database.name, app.name)
      @database.app_databases.find_by(app_record: app)&.destroy

      redirect_to dashboard_resource_path(@database), notice: "Unlinked #{app.name} from #{@database.name}."
    rescue => e
      redirect_to dashboard_resource_path(@database), alert: "Unlink failed: #{e.message}"
    end

    private

    def database_params
      params.require(:database_service).permit(:name, :service_type)
    end

    def fetch_info
      client = Dokku::Client.new(@database.server)
      Dokku::Databases.new(client).info(@database.service_type, @database.name)
    rescue => e
      Rails.logger.warn "Failed to fetch database info for #{@database.name}: #{e.message}"
      {}
    end
  end
end

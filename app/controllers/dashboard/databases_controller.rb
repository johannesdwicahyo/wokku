module Dashboard
  class DatabasesController < BaseController
    def index
      @databases = policy_scope(DatabaseService).includes(:server)
      @database = DatabaseService.new
      @servers = policy_scope(Server)
    end

    def show
      @database = DatabaseService.find(params[:id])
      authorize @database
    end

    def new
      @database = DatabaseService.new
      @servers = policy_scope(Server)
    end

    def create
      server = policy_scope(Server).find(params[:database_service][:server_id])
      @database = DatabaseService.new(database_params.merge(server: server))
      authorize @database

      if @database.save
        redirect_to dashboard_database_path(@database), notice: "Database created successfully."
      else
        @servers = policy_scope(Server)
        @databases = policy_scope(DatabaseService).includes(:server)
        render :index, status: :unprocessable_entity
      end
    end

    def destroy
      @database = DatabaseService.find(params[:id])
      authorize @database
      @database.destroy
      redirect_to dashboard_databases_path, notice: "Database deleted successfully."
    end

    private

    def database_params
      params.require(:database_service).permit(:name, :service_type)
    end
  end
end

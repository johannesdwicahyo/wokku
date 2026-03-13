module Dashboard
  class ConfigController < BaseController
    before_action :set_app

    def index
      authorize @app, :show?
      @env_vars = @app.env_vars
    end

    private

    def set_app
      @app = AppRecord.find(params[:app_id])
    end
  end
end

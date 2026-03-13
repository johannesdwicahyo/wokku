module Dashboard
  class LogsController < BaseController
    before_action :set_app

    def show
      authorize @app, :show?
    end

    private

    def set_app
      @app = AppRecord.find(params[:app_id])
    end
  end
end

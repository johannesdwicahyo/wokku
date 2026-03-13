module Dashboard
  class ReleasesController < BaseController
    before_action :set_app

    def index
      authorize @app, :show?
      @releases = @app.releases.includes(:deploy).order(version: :desc)
    end

    private

    def set_app
      @app = AppRecord.find(params[:app_id])
    end
  end
end

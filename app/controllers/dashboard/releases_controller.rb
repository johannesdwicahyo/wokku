module Dashboard
  class ReleasesController < BaseController
    before_action :set_app

    def index
      authorize @app, :show?
      @releases = @app.releases.includes(:deploy).order(version: :desc)
    end

    def deploy
      authorize @app, :update?

      release = @app.releases.create!(description: "Manual deploy via dashboard")
      deploy = @app.deploys.create!(release: release, status: :pending)
      DeployJob.perform_later(deploy.id)

      redirect_to dashboard_app_releases_path(@app), notice: "Deploy triggered. Building..."
    end

    private

    def set_app
      @app = AppRecord.find(params[:app_id])
    end
  end
end

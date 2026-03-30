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

    def rollback
      authorize @app, :update?

      target_release = @app.releases.find(params[:id])
      new_release = @app.releases.create!(description: "Rollback to v#{target_release.version}")
      deploy = @app.deploys.create!(release: new_release, status: :pending)
      DeployJob.perform_later(deploy.id)

      redirect_to dashboard_app_releases_path(@app), notice: "Rolling back to v#{target_release.version}..."
    end

    private

    def set_app
      @app = AppRecord.find(params[:app_id])
    end
  end
end

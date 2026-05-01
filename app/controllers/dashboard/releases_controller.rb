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
      target_deploy = target_release.deploy || @app.deploys.where(release_id: target_release.id).order(created_at: :desc).first
      target_sha = target_deploy&.commit_sha

      if target_sha.blank?
        redirect_to dashboard_app_releases_path(@app),
          alert: "Cannot rollback to v#{target_release.version}: no commit SHA recorded."
        return
      end

      new_release = @app.releases.create!(description: "Rollback to v#{target_release.version} (#{target_sha[0..6]})")
      deploy = @app.deploys.create!(release: new_release, status: :pending, commit_sha: target_sha)
      DeployJob.perform_later(deploy.id, commit_sha: target_sha)

      redirect_to dashboard_app_releases_path(@app), notice: "Rolling back to v#{target_release.version}..."
    end

    private

    def set_app
      @app = AppRecord.find(params[:app_id])
    end
  end
end

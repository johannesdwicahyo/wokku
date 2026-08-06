module Dashboard
  class ReleasesController < BaseController
    before_action :set_app

    def index
      authorize @app, :show?
      @releases = @app.releases.includes(:deploy).order(version: :desc)
      # Currently-deployed release = newest release whose deploy succeeded.
      # Surfaced as a "Current" badge so the rollback target is obvious.
      @current_release_id = @releases.find { |r| r.deploy&.status == "succeeded" }&.id
    end

    def deploy
      authorize @app, :update?

      release = @app.releases.create!(description: "Manual deploy via dashboard")
      deploy = @app.deploys.create!(release: release, status: :pending)
      DeployJob.perform_later(deploy.id)

      redirect_to dashboard_app_releases_path(@app), notice: "Deploy triggered. Building..."
    end

    # Real rollback (Track A Phase 4a Task 4, dashboard rider): redeploys the
    # target release's recorded artifact via RollbackArtifactResolver +
    # RollbackDeployJob — the same real path Api::V1::ReleasesController#rollback
    # uses — instead of the old placebo (DeployJob with a commit_sha that
    # just ran `ps:rebuild` on HEAD regardless of which release was picked).
    def rollback
      authorize @app, :update?

      target_release = @app.releases.find(params[:id])
      target_deploy = target_release.deploy || @app.deploys.where(release_id: target_release.id).order(created_at: :desc).first
      result = RollbackArtifactResolver.call(app_record: @app, release: target_release, target_deploy: target_deploy)

      unless result.artifact_available?
        redirect_to dashboard_app_releases_path(@app), alert: result.hint
        return
      end

      new_release = @app.releases.create!(description: "Rollback to v#{target_release.version}")
      deploy = @app.deploys.create!(
        release: new_release,
        status: :pending,
        image_ref: result.image_ref,
        archive_key: result.archive_key
      )
      RollbackDeployJob.perform_later(app_id: @app.id, deploy_id: deploy.id)

      redirect_to dashboard_app_releases_path(@app), notice: "Rolling back to v#{target_release.version}..."
    end

    private

    def set_app
      @app = AppRecord.find(params[:app_id])
    end
  end
end

module Api
  module V1
    class ReleasesController < BaseController
      before_action :set_app_record

      def index
        authorize @app_record, :show?
        releases = @app_record.releases.order(version: :desc)
        render json: releases
      end

      def show
        release = @app_record.releases.find(params[:id])
        authorize release
        render json: release
      end

      # Real rollback (Track A Phase 4a Task 4): redeploys the target
      # release's *recorded artifact* rather than the old placebo that just
      # ran `ps:rebuild` on HEAD regardless of the release picked. Artifact
      # resolution (image tag still on host? archive still in storage?) is
      # shared with Dashboard::ReleasesController#rollback via
      # RollbackArtifactResolver — see that class for the exact order and
      # the 422 rollback_artifact_missing hint wording.
      #
      # The new Deploy row records whichever artifact resolution picked, so
      # a rollback deploy is itself a valid future rollback target.
      def rollback
        release = @app_record.releases.find(params[:id])
        authorize release

        target_deploy = release.deploy || @app_record.deploys.where(release_id: release.id).order(created_at: :desc).first
        result = RollbackArtifactResolver.call(app_record: @app_record, release: release, target_deploy: target_deploy)

        return render_api_error(:rollback_artifact_missing, hint: result.hint) unless result.artifact_available?

        new_release = @app_record.releases.create!(description: "Rollback to v#{release.version}")
        new_deploy = @app_record.deploys.create!(
          release: new_release,
          status: :pending,
          image_ref: result.image_ref,
          archive_key: result.archive_key
        )
        RollbackDeployJob.perform_later(app_id: @app_record.id, deploy_id: new_deploy.id)

        render json: new_release, status: :created
      end

      private

      def set_app_record
        @app_record = policy_scope(AppRecord).lookup!(params[:app_id])
      end
    end
  end
end

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

      def rollback
        release = @app_record.releases.find(params[:id])
        authorize release

        # Find the original deploy for the target release to get its commit_sha
        target_deploy = release.deploy || @app_record.deploys.where(release_id: release.id).order(created_at: :desc).first
        target_sha = target_deploy&.commit_sha

        if target_sha.blank?
          return render json: {
            error: "Cannot rollback: no commit SHA recorded for v#{release.version}. Only releases with recorded commits can be rolled back."
          }, status: :unprocessable_entity
        end

        new_release = @app_record.releases.create!(
          description: "Rollback to v#{release.version} (#{target_sha[0..6]})"
        )
        new_deploy = @app_record.deploys.create!(
          release: new_release,
          status: :pending,
          commit_sha: target_sha
        )
        DeployJob.perform_later(new_deploy.id, commit_sha: target_sha)

        render json: new_release, status: :created
      end

      private

      def set_app_record
        @app_record = AppRecord.lookup!(params[:app_id])
      end
    end
  end
end

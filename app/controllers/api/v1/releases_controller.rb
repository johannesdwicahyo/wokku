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

        new_release = @app_record.releases.create!(
          description: "Rollback to v#{release.version}"
        )
        deploy = @app_record.deploys.create!(release: new_release, status: :pending)
        DeployJob.perform_later(deploy.id)

        render json: new_release, status: :created
      end

      private

      def set_app_record
        @app_record = AppRecord.find(params[:app_id])
      end
    end
  end
end

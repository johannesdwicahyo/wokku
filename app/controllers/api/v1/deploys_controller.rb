module Api
  module V1
    class DeploysController < BaseController
      def index
        app = AppRecord.lookup!(params[:app_id])
        authorize app, :show?
        deploys = app.deploys.order(created_at: :desc).limit(20)
        render json: deploys.as_json(only: [ :id, :status, :commit_sha, :description, :started_at, :finished_at, :created_at ])
      end

      def show
        app = AppRecord.lookup!(params[:app_id])
        authorize app, :show?
        deploy = app.deploys.find(params[:id])
        render json: deploy.as_json(only: [ :id, :status, :commit_sha, :description, :log, :started_at, :finished_at, :created_at ])
      end
    end
  end
end

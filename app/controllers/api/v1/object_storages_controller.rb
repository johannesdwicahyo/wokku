module Api
  module V1
    class ObjectStoragesController < BaseController
      before_action :require_feature
      before_action :set_app
      before_action :set_bucket, except: :create
      before_action :require_active, only: %i[update rotate]

      def show
        authorize @app, :show?
        render json: payload(@bucket)
      end

      def create
        authorize @app, :update?
        return render json: { error: "App already has object storage" }, status: :conflict if @app.object_storage_bucket

        bucket = ObjectStorage::Provisioner.create!(@app)
        track("object_storage.created", target: @app, team: @app.team)
        render json: payload(bucket), status: :accepted
      end

      def update
        authorize @app, :update?
        status, message = @bucket.quota_error(params[:quota_gb])
        return render json: { error: message }, status: status if status

        begin
          ObjectStorage::Provisioner.resize!(@bucket, params[:quota_gb])
        rescue ObjectStorage::Error
          return render json: { error: ObjectStorageBucket::UNAVAILABLE }, status: :service_unavailable
        end
        track("object_storage.resized", target: @app, metadata: { quota_gb: @bucket.quota_gb }, team: @app.team)
        render json: payload(@bucket)
      end

      def rotate
        authorize @app, :update?
        ObjectStorage::RotateJob.perform_later(@bucket.id)
        track("object_storage.rotated", target: @app, team: @app.team)
        render json: payload(@bucket), status: :accepted
      end

      def destroy
        authorize @app, :update?
        @bucket.update!(status: "deleting")
        ObjectStorage::DeprovisionJob.perform_later(@bucket.id)
        track("object_storage.destroyed", target: @app, team: @app.team)
        render json: payload(@bucket), status: :accepted
      end

      private

      def require_feature
        render_api_error(:not_found) unless Wokku.config.object_storage?
      end

      def set_app
        @app = policy_scope(AppRecord).lookup!(params[:app_id])
      end

      def set_bucket
        @bucket = @app.object_storage_bucket or raise ActiveRecord::RecordNotFound
      end

      def require_active
        render json: { error: @bucket.not_ready_message }, status: :conflict unless @bucket.active?
      end

      def payload(bucket) = bucket.as_api_json(reveal: reveal_secrets?(@app))
    end
  end
end

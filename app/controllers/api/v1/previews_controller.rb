module Api
  module V1
    class PreviewsController < BaseController
      before_action :set_app

      def index
        authorize @app, :show?
        rows = @app.preview_apps.order(pr_number: :desc).map { |p| ::Api::V1::Serializers::PreviewApp.new(p).call }
        render json: rows
      end

      def destroy
        authorize @app, :update?
        pr_number = params[:pr_number].to_i
        preview = @app.preview_apps.find_by(pr_number: pr_number)
        return render_api_error(:not_found, message: "No preview with PR ##{pr_number}") unless preview

        ::Preview::CleanupJob.perform_later(@app.id, pr_number)
        Activity.log(user: current_user, team: @app.team, action: "app.preview_destroy_queued", target: @app,
                     metadata: { pr_number: pr_number })
        render json: { message: "Preview destroy queued" }, status: :accepted
      end

      private

      def set_app
        @app = policy_scope(AppRecord).lookup!(params[:app_id])
      end
    end
  end
end

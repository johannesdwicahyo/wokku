module Dashboard
  class PreviewManagementController < BaseController
    def index
      @app = AppRecordPolicy::Scope.new(current_user, AppRecord).resolve.find(params[:app_id])
      authorize @app, :show?
      @previews = @app.preview_apps.order(pr_number: :desc)
    end

    def destroy
      parent  = AppRecordPolicy::Scope.new(current_user, AppRecord).resolve.find(params[:app_id])
      preview = parent.preview_apps.find(params[:id])
      authorize preview, :destroy?
      Preview::CleanupJob.perform_later(parent.id, preview.pr_number)
      redirect_to dashboard_app_previews_path(parent), notice: "Preview destroy queued"
    end
  end
end

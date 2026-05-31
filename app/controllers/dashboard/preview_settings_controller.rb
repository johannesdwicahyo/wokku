module Dashboard
  class PreviewSettingsController < BaseController
    def update
      app = AppRecordPolicy::Scope.new(current_user, AppRecord).resolve.find(params[:app_id])
      authorize app, :update?
      if app.update(preview_params)
        redirect_to dashboard_app_previews_path(app), notice: "Preview settings updated"
      else
        redirect_to dashboard_app_previews_path(app), alert: app.errors.full_messages.join(", ")
      end
    end

    private

    def preview_params
      params.require(:app_record).permit(:preview_enabled, :database_strategy)
    end
  end
end

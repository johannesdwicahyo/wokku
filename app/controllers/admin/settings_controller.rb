module Admin
  # Install-wide settings. Add-on scripts are raw HTML rendered on every
  # dashboard/docs page — admin-only by design (the admin already controls
  # the whole install).
  class SettingsController < BaseController
    def show
      @setting = SiteSetting.current
    end

    def update
      SiteSetting.current.update!(params.require(:site_setting).permit(:body_scripts))
      redirect_to admin_settings_path, notice: "Settings saved"
    end
  end
end

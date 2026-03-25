module Dashboard
  class LocalesController < BaseController
    def update
      locale = params[:locale]
      if I18n.available_locales.include?(locale.to_sym)
        cookies[:locale] = { value: locale, expires: 1.year.from_now }
      end
      redirect_back fallback_location: dashboard_apps_path
    end
  end
end

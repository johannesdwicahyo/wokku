module Dashboard
  class LocalesController < BaseController
    def update
      locale = params[:locale].to_s
      if I18n.available_locales.include?(locale.to_sym)
        cookies[:locale] = { value: locale, expires: 1.year.from_now }
        current_user.update_column(:locale, locale)
      end
      redirect_back fallback_location: dashboard_root_path
    end
  end
end

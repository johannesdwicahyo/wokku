class LocalesController < ApplicationController
  def update
    locale = params[:locale].to_s
    if I18n.available_locales.include?(locale.to_sym)
      cookies[:locale] = { value: locale, expires: 1.year.from_now }
      current_user.update_column(:locale, locale) if user_signed_in?
    end
    redirect_back fallback_location: root_path
  end
end

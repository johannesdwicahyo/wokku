class LocalesController < ApplicationController
  def update
    locale = params[:locale].to_s
    if I18n.available_locales.include?(locale.to_sym)
      cookies[:locale] = { value: locale, expires: 1.year.from_now }
      current_user.update_column(:locale, locale) if user_signed_in?
    end
    redirect_to back_path, allow_other_host: false
  end

  private

  # Same-host referer path with ?locale= dropped (it would override the cookie
  # in Localizable#set_locale); every other query param is kept.
  def back_path
    uri = URI.parse(request.referer.to_s)
    return root_path unless uri.host == request.host && uri.path.present?
    query = Rack::Utils.parse_query(uri.query).except("locale")
    query.empty? ? uri.path : "#{uri.path}?#{query.to_query}"
  rescue URI::InvalidURIError
    root_path
  end
end

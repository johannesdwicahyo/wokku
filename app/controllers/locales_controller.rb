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

  # Same-host referer path with ?locale= (Localizable#set_locale) and the
  # docs' ?lang= (DocsController#resolve_locale) dropped, since either would
  # override the cookie; every other query param is kept.
  def back_path
    uri = URI.parse(request.referer.to_s)
    return root_path unless uri.host == request.host && uri.path.present?
    # collapse leading slashes: "//evil.com" would be a protocol-relative redirect
    path = "/" + uri.path.sub(%r{\A/+}, "")
    query = Rack::Utils.parse_query(uri.query).except("locale", "lang")
    query.empty? ? path : "#{path}?#{query.to_query}"
  rescue URI::InvalidURIError
    root_path
  end
end

module Localizable
  extend ActiveSupport::Concern

  included do
    before_action :set_locale
  end

  private

  def set_locale
    locale = params[:locale] || cookies[:locale] || extract_locale_from_header || I18n.default_locale
    I18n.locale = locale.to_sym if I18n.available_locales.include?(locale.to_sym)
  end

  def extract_locale_from_header
    accept = request.env["HTTP_ACCEPT_LANGUAGE"]
    return nil unless accept
    preferred = accept.scan(/[a-z]{2}/).first
    preferred if I18n.available_locales.include?(preferred&.to_sym)
  end
end

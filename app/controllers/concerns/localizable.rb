module Localizable
  extend ActiveSupport::Concern

  LOCALE_CURRENCY = { en: "usd", id: "idr" }.freeze

  included do
    before_action :set_locale
    helper_method :current_currency
  end

  private

  def set_locale
    locale = params[:locale].presence || cookies[:locale] || extract_locale_from_header || I18n.default_locale
    locale = locale.to_sym
    locale = I18n.default_locale unless I18n.available_locales.include?(locale)

    I18n.locale = locale
    @currency = LOCALE_CURRENCY[locale] || "usd"
  end

  def current_currency
    @currency || "usd"
  end

  def extract_locale_from_header
    accept = request.env["HTTP_ACCEPT_LANGUAGE"]
    return nil unless accept
    preferred = accept.scan(/[a-z]{2}/).first
    preferred if I18n.available_locales.include?(preferred&.to_sym)
  end
end

module Localizable
  extend ActiveSupport::Concern

  # Default currency when a user hasn't chosen one yet.
  LOCALE_DEFAULT_CURRENCY = { en: "usd", id: "idr" }.freeze

  included do
    before_action :set_locale
    helper_method :current_currency
  end

  private

  def set_locale
    locale = params[:locale].presence ||
             (user_signed_in? && current_user.locale.presence) ||
             cookies[:locale] ||
             extract_locale_from_header ||
             I18n.default_locale
    locale = locale.to_sym
    locale = I18n.default_locale unless I18n.available_locales.include?(locale)
    I18n.locale = locale
  end

  # Returns the current user's chosen currency. Falls back to a locale-based
  # default for signed-out visitors (landing / pricing page).
  def current_currency
    return current_user.currency if user_signed_in? && current_user.currency.present?
    LOCALE_DEFAULT_CURRENCY[I18n.locale] || "usd"
  end

  def extract_locale_from_header
    accept = request.env["HTTP_ACCEPT_LANGUAGE"]
    return nil unless accept
    preferred = accept.scan(/[a-z]{2}/).first
    preferred if I18n.available_locales.include?(preferred&.to_sym)
  end
end

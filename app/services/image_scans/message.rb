module ImageScans
  # The one localized text for the image_scan_critical event, shared by chat
  # channels, email and push. context: app_id, app_name, count, ids, locale.
  module Message
    module_function

    def body(context)
      c = context || {}
      g = ->(k) { c[k] || c[k.to_sym] }
      url = link(g.("app_id"))
      I18n.t(url ? "apps.security.notify_critical" : "apps.security.notify_critical_no_link",
             locale: locale(c), app: g.("app_name"), count: g.("count"), ids: g.("ids"), url: url)
    end

    def subject(context)
      c = context || {}
      I18n.t("apps.security.notify_critical_subject", locale: locale(c), app: c["app_name"] || c[:app_name], count: c["count"] || c[:count])
    end

    def title(context) = I18n.t("apps.security.notify_critical_title", locale: locale(context || {}))

    def link(app_id)
      base = NotifyJob.base_url
      return unless base && app_id
      "#{base}#{Rails.application.routes.url_helpers.dashboard_app_image_scan_path(app_id)}"
    end

    def locale(c) = c["locale"].presence || c[:locale].presence || I18n.default_locale
  end
end

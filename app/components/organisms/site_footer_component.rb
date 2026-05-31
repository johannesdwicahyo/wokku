module Organisms
  class SiteFooterComponent < ApplicationComponent
    # Ordered href arrays keyed by column — position-matched to locale link labels.
    # Where no dedicated page exists the nearest public page is used; never "#".
    LINK_HREFS = {
      product:         ["/templates", "/pricing", "/changelog", "/status"],
      solutions:       ["/lp/zero-ops", "/lp/ai-native", "/lp/flat-price", "/lp/one-click-apps"],
      getting_started: ["/users/sign_in", "/templates", "/pricing", "/faq"],
      learn:           ["/docs", "/docs", "/faq", "https://github.com/johannesdwicahyo/wokku"],
      company:         ["/contact", "/privacy", "/terms", "/refund"]
    }.freeze

    COL_KEYS = %i[product solutions getting_started learn company].freeze

    def cols
      COL_KEYS.map do |k|
        labels = t("footer.cols.#{k}.links")
        hrefs  = LINK_HREFS[k]
        links  = labels.zip(hrefs).map { |label, href| { label: label, href: href } }
        { key: k, head: t("footer.cols.#{k}.head"), links: links }
      end
    end
  end
end

module Organisms
  class SiteNavComponent < ApplicationComponent
    def initialize(active: nil)
      @active = active
    end
    attr_reader :active

    def links
      [
        [:pricing,   t('nav.pricing'),   '/pricing'],
        [:templates, t('nav.templates'), '/templates'],
        [:docs,      "#{t('nav.docs')} ↗", "/docs"],
        [:github,    "#{t('nav.github')} ↗", "https://github.com/johannesdwicahyo/wokku"],
      ]
    end
  end
end

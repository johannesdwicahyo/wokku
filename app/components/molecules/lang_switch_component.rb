module Molecules
  class LangSwitchComponent < ApplicationComponent
    def initialize(current: I18n.locale)
      @current = current.to_sym
    end

    def active?(locale)
      @current == locale
    end

    def cell_classes(locale)
      base = "px-2.5 py-1 text-[11px] font-semibold tracking-tight cursor-pointer transition-colors"
      if active?(locale)
        "#{base} bg-ink text-bg"
      else
        "#{base} bg-transparent text-ink-soft hover:text-ink"
      end
    end
  end
end

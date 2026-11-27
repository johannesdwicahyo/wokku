module Molecules
  class LangSwitchComponent < ApplicationComponent
    def initialize(current: I18n.locale)
      @current = current.to_sym
    end

    def active?(locale)
      @current == locale
    end

    # Full accessible name, in the option's own language.
    def t_label(locale)
      locale == :en ? "English" : "Bahasa Indonesia"
    end

    def cell_classes(locale)
      base = "px-2.5 py-1 min-h-6 inline-flex items-center text-[11px] font-semibold tracking-tight cursor-pointer transition-colors focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-ink"
      if active?(locale)
        "#{base} bg-ink text-bg"
      else
        "#{base} bg-transparent text-ink-soft hover:text-ink"
      end
    end
  end
end

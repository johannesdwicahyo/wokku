module Molecules
  class SidebarNavItemComponent < ApplicationComponent
    # ponytail: icon ignored; removed in Task 4 when ConsoleSidebarComponent is deleted
    def initialize(label:, key:, active: false, href: "#", external: false, icon: nil, count: nil)
      @label = label
      @key = key
      @active = active
      @href = href
      @external = external
      @count = count
    end
    attr_reader :label, :key, :active, :href, :external, :count

    def classes
      base = "flex items-center gap-2.5 min-h-[38px] px-2.5 text-sm border-l-2 transition-colors hover:bg-white/[.035] hover:text-ink"
      if active
        "#{base} border-live bg-live/7 text-ink"
      else
        "#{base} border-transparent text-ink-soft"
      end
    end

    def light_classes
      cx("w-2 h-2 rounded-[2px] shrink-0", active ? "bg-live wk-glow-live" : "bg-[#2A302A]")
    end

    def link_attrs
      attrs = external ? { target: "_blank", rel: "noopener" } : {}
      active ? attrs.merge("aria-current": "page") : attrs
    end
  end
end

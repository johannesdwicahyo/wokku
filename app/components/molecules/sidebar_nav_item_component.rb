module Molecules
  class SidebarNavItemComponent < ApplicationComponent
    def initialize(label:, key:, active: false, href: "#", external: false, icon: nil, count: nil)
      @label = label
      @key = key
      @active = active
      @href = href
      @external = external
      @icon = icon
      @count = count
    end
    attr_reader :label, :key, :active, :href, :external, :icon, :count

    def classes
      base = "flex items-center gap-2.5 px-2 py-[7px] text-sm rounded transition-colors"
      if @active
        "#{base} bg-bg-deep text-ink font-semibold"
      else
        "#{base} text-ink-soft font-medium hover:bg-bg-deep"
      end
    end
  end
end

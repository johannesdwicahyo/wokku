module Molecules
  class SidebarNavItemComponent < ApplicationComponent
    def initialize(label:, key:, active: false, href: "#", external: false)
      @label = label
      @key = key
      @active = active
      @href = href
      @external = external
    end
    attr_reader :label, :key, :active, :href, :external

    def classes
      base = "flex items-center gap-2 px-3.5 py-2 font-mono text-sm border-l-2 transition-colors"
      if @active
        "#{base} bg-accent-soft border-accent text-accent"
      else
        "#{base} border-transparent text-ink-soft hover:text-ink"
      end
    end
  end
end

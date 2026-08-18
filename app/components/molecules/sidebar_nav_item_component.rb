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
      base = "flex items-center gap-2 px-3.5 py-2 text-sm rounded-md transition-colors"
      if @active
        "#{base} bg-rule-soft text-ink font-medium"
      else
        "#{base} text-ink-soft hover:bg-rule-soft/60"
      end
    end
  end
end

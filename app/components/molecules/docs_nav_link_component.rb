module Molecules
  class DocsNavLinkComponent < ApplicationComponent
    def initialize(label:, href:, active: false)
      @label  = label
      @href   = href
      @active = active
    end
    attr_reader :label, :href, :active
  end
end

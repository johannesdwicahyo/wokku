module Molecules
  class BreadcrumbComponent < ApplicationComponent
    # crumbs: Array of [label, href] pairs. href may be nil for the current page.
    def initialize(crumbs:)
      @crumbs = crumbs
    end
    attr_reader :crumbs
  end
end

module Molecules
  class CodeTabsComponent < ApplicationComponent
    def initialize(tabs:)
      @tabs = tabs
    end
    attr_reader :tabs
  end
end

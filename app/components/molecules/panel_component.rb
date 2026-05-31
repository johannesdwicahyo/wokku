module Molecules
  class PanelComponent < ApplicationComponent
    def initialize(label: nil, kicker: nil)
      @label = label
      @kicker = kicker
    end
    attr_reader :label, :kicker
  end
end

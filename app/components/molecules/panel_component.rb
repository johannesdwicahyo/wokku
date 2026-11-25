module Molecules
  class PanelComponent < ApplicationComponent
    def initialize(label: nil, kicker: nil, ticks: true)
      @label = label
      @kicker = kicker
      @ticks = ticks
    end
    attr_reader :label, :kicker, :ticks
  end
end

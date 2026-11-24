module Molecules
  class ReadoutComponent < ApplicationComponent
    def initialize(label:, value:, sub: nil, tone: :default)
      @label = label
      @value = value
      @sub = sub
      @tone = tone
    end

    attr_reader :label, :value, :sub

    def value_class = @tone == :live ? "text-live" : "text-ink"
  end
end

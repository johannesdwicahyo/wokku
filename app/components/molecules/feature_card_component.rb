module Molecules
  class FeatureCardComponent < ApplicationComponent
    def initialize(num:, title:, body:, position:)
      @num = num
      @title = title
      @body = body
      @position = position
    end
    attr_reader :num, :title, :body, :position

    def border_classes
      classes = []
      classes << "md:border-r-1.5 md:border-ink" unless @position[:last_col]
      classes << "md:border-b-1.5 md:border-ink" unless @position[:last_row]
      classes << "border-b-1.5 border-ink md:border-b-0" unless @position[:overall_last]
      classes.join(" ")
    end
  end
end

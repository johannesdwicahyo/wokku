module Atoms
  class KbdComponent < ApplicationComponent
    def initialize(label = nil)
      @label = label
    end

    def call
      content_tag(:kbd, @label || content)
    end
  end
end

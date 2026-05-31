module Organisms
  class DocsTocComponent < ApplicationComponent
    def initialize(items:)
      @items = items
    end
    attr_reader :items
  end
end

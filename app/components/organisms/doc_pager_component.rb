module Organisms
  # Prev/next links at the bottom of a doc page. The controller resolves
  # both items from the sidebar YAML; the component just renders.
  #
  # prev_item: { "title", "path" } or nil
  # next_item: { "title", "path" } or nil
  class DocPagerComponent < ApplicationComponent
    def initialize(prev_item:, next_item:)
      @prev_item = prev_item
      @next_item = next_item
    end
    attr_reader :prev_item, :next_item
  end
end

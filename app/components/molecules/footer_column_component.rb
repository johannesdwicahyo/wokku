module Molecules
  class FooterColumnComponent < ApplicationComponent
    def initialize(head:, links:)
      @head = head
      @links = Array(links)
    end
    attr_reader :head, :links
  end
end

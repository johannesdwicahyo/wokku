module Molecules
  class TemplateCardComponent < ApplicationComponent
    def initialize(name:, icon:, category:)
      @name = name
      @icon = icon
      @category = category
    end
    attr_reader :name, :icon, :category

    def cmd; "$ wokku deploy #{@name.downcase}"; end
  end
end

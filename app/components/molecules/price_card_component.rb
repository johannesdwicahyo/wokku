module Molecules
  class PriceCardComponent < ApplicationComponent
    def initialize(name:, price:, desc:, pays_in:, highlight: false, you_label: nil, month_suffix: "mo")
      @name = name
      @price = price
      @desc = desc
      @pays_in = pays_in
      @highlight = highlight
      @you_label = you_label
      @month_suffix = month_suffix
    end
    attr_reader :name, :price, :desc, :pays_in, :highlight, :you_label, :month_suffix
  end
end

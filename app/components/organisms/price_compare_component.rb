module Organisms
  class PriceCompareComponent < ApplicationComponent
    ROWS = [:heroku, :vercel, :railway, :wokku].freeze
    def rows; ROWS; end
  end
end

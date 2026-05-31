module Organisms
  class AppRuntimeComponent < ApplicationComponent
    SECTIONS = %i[logs metrics terminal scaling].freeze

    def initialize(app:, active: :logs)
      @app    = app
      @active = active.to_sym
    end

    attr_reader :app, :active
  end
end

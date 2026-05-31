module Organisms
  class AppDeployComponent < ApplicationComponent
    SECTIONS = %i[releases github previews config].freeze

    def initialize(app:, active: :releases)
      @app    = app
      @active = active.to_sym
    end

    attr_reader :app, :active
  end
end

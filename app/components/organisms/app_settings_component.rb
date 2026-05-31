module Organisms
  class AppSettingsComponent < ApplicationComponent
    SECTIONS = %i[domains checks scheduled_tasks log_drains transfer].freeze

    def initialize(app:, active: :domains)
      @app    = app
      @active = active.to_sym
    end

    attr_reader :app, :active
  end
end

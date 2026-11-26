# frozen_string_literal: true

module Organisms
  # Add-ons attached to the app; env var is "<alias_name>_URL" (see
  # Dashboard::DatabasesController#attach).
  class AppConnectedComponent < ApplicationComponent
    def initialize(app:)
      @app = app
    end
    attr_reader :app

    def links = @links ||= app.app_databases.includes(:database_service).to_a
    def env_var(link) = "#{link.alias_name}_URL"
    def state(svc) = svc.running? ? :running : (svc.error? ? :crashed : (svc.stopped? ? :stopped : :deploying))
  end
end

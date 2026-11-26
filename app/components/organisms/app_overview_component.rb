module Organisms
  # Control-room overview: status board, metrics, processes, live log on the
  # left; deploys, connected, domains, resources (+ backups / storage) right.
  class AppOverviewComponent < ApplicationComponent
    def initialize(app:, releases:, current_release:, domains:, stats:, can_update:)
      @app, @releases, @current_release, @domains, @stats, @can_update =
        app, releases, current_release, domains, stats, can_update
    end
    attr_reader :app, :releases, :current_release, :domains, :stats, :can_update

    # Same source as LogsController#glance_process.
    def process_types
      (app.dyno_allocations.map(&:process_type) + app.process_scales.map(&:process_type)).uniq
    end

    def databases? = app.app_databases.exists?

    def storage
      Wokku.config.object_storage? ? app.object_storage_bucket : nil
    end
  end
end

module Organisms
  module App
    class SharedAddonCardComponent < ApplicationComponent
      def initialize(app:, database_service:)
        @app = app
        @db  = database_service
      end

      private

      attr_reader :app, :db

      def upgradeable?
        %w[postgres redis].include?(db.service_type) && db.status == "running"
      end

      def in_progress?
        db.status.start_with?("upgrading_")
      end

      def status_label
        case db.status
        when "upgrading_provisioning" then "Step 1/5: Provisioning dedicated container…"
        when "upgrading_migrating"    then "Step 2/5: Migrating data…"
        when "upgrading_cutover"      then "Step 4/5: Switching app over…"
        when "upgrading_failed"       then "Upgrade failed — see details below."
        when "pending_destroy"        then "Shared tenant pending cleanup."
        else                               "Running"
        end
      end

      def engine_label
        db.service_type.capitalize
      end

      def upgrade_path
        case db.service_type
        when "postgres" then helpers.upgrade_to_dedicated_postgres_addon_dashboard_app_path(app)
        when "redis"    then helpers.upgrade_to_dedicated_redis_addon_dashboard_app_path(app)
        end
      end
    end
  end
end

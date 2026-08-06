# frozen_string_literal: true

module Dashboard
  module Apps
    class AddonsController < Dashboard::BaseController
      before_action :set_app
      before_action :authorize_upgrade

      # POST /dashboard/apps/:id/addons/postgres/upgrade
      #
      # Kicks off the shared → dedicated Postgres upgrade flow. The
      # DatabaseServiceUpgrade service handles pre-flight checks (slot
      # availability, idempotency guard) synchronously; if they pass, it
      # enqueues UpgradeSharedPgToDedicatedJob and returns the reserved
      # dedicated DatabaseService. On failure it raises an UpgradeError
      # subclass whose UI_MESSAGE is forwarded to the user as a flash alert.
      def upgrade_to_dedicated
        DatabaseServiceUpgrade.call(app: @app, user: current_user)
        redirect_to dashboard_app_domains_path(@app),
                    notice: "Upgrading shared Postgres to dedicated — this takes 1–2 minutes."
      rescue UpgradeError => e
        message = e.message.presence ||
                  (e.class.const_defined?(:UI_MESSAGE) ? e.class::UI_MESSAGE : "Upgrade failed.")
        redirect_to dashboard_app_domains_path(@app), alert: message
      end

      # POST /dashboard/apps/:id/addons/redis/upgrade
      #
      # Same flow as upgrade_to_dedicated but for the Redis engine.
      def upgrade_redis_to_dedicated
        DatabaseServiceUpgrade.call(app: @app, user: current_user, engine: "redis")
        redirect_to dashboard_app_domains_path(@app),
                    notice: "Upgrading shared Redis to dedicated — this takes about a minute."
      rescue UpgradeError => e
        message = e.message.presence ||
                  (e.class.const_defined?(:UI_MESSAGE) ? e.class::UI_MESSAGE : "Upgrade failed.")
        redirect_to dashboard_app_domains_path(@app), alert: message
      end

      private

      def set_app
        # When nested as `on: :member`, Rails passes the parent app id as :id.
        @app = AppRecord.lookup!(params[:id])
      end

      def authorize_upgrade
        authorize @app, :upgrade_to_dedicated_addon?
      end
    end
  end
end

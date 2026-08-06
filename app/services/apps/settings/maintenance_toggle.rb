module Apps
  module Settings
    # W7 Phase 3: maintenance mode is a real router flag (was the dokku
    # maintenance plugin over SSH). Routers::ConfigBuilder emits
    # `"maintenance" => true` for this app; wokkud renders its vhosts as a
    # Caddy static 503 page instead of reverse_proxy. Takes effect on the
    # next router sync (heartbeat, ~15s) once the agent understands the
    # field — old agents ignore it (flag is dark until the agent rollout).
    class MaintenanceToggle
      def initialize(app)
        @app = app
      end

      def enable!
        @app.update!(maintenance_mode: true)
        true
      end

      def disable!
        @app.update!(maintenance_mode: false)
        false
      end

      def enabled?
        @app.maintenance_mode?
      end
    end
  end
end

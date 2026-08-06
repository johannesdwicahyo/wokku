module Apps
  module Settings
    # W7 Phase 3: pure control-plane bookkeeping (was dokku redirect:set/
    # unset/report over SSH). Caddy — rendered by wokkud from
    # Routers::ConfigBuilder — auto-redirects HTTP→HTTPS for every vhost
    # today, so `https_redirect` is recorded intent: it ships dark until the
    # router honors opt-out.
    class HttpsToggle
      def initialize(app)
        @app = app
      end

      def enable!
        @app.update!(https_redirect: true)
        true
      end

      def disable!
        @app.update!(https_redirect: false)
        false
      end

      def enabled?
        @app.https_redirect?
      end
    end
  end
end

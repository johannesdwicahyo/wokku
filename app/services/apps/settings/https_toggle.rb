module Apps
  module Settings
    # Caddy (rendered by wokkud from Routers::ConfigBuilder) redirects
    # HTTP→HTTPS for every vhost and has no opt-out, so disabling is refused
    # instead of recording a setting nothing reads.
    class HttpsToggle
      def initialize(app)
        @app = app
      end

      def enable!
        @app.update!(https_redirect: true)
        true
      end

      def disable!
        raise Error.new("HTTPS redirect can't be turned off: every app is served over HTTPS.", code: :not_supported)
      end

      def enabled?
        @app.https_redirect?
      end
    end
  end
end

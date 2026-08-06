module Apps
  module Settings
    class CdnToggle
      def initialize(app)
        @app = app
      end

      def enable!
        return true if @app.cloudflare_proxied?
        @app.update!(cloudflare_proxied: true)
        UpdateAppCdnJob.perform_later(@app.id, true)
        true
      end

      def disable!
        return false unless @app.cloudflare_proxied?
        @app.update!(cloudflare_proxied: false)
        UpdateAppCdnJob.perform_later(@app.id, false)
        false
      end

      def enabled?
        @app.cloudflare_proxied?
      end
    end
  end
end

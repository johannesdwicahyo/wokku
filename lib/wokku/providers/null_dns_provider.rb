module Wokku
  class Providers
    # OSS default: Wokku does not manage DNS for you. Records are a no-op;
    # the self-hoster points their own DNS. Managed injects Cloudflare::DnsProvider.
    class NullDnsProvider
      def create_app_record(app_name, server_ip)
        Rails.logger.info("[dns] manual DNS: point #{app_name} at #{server_ip} yourself (no DNS provider configured)")
        nil
      end

      def delete_app_record(app_name)
        Rails.logger.info("[dns] manual DNS: remove the record for #{app_name} yourself (no DNS provider configured)")
        nil
      end

      def set_proxied!(app_name, proxied:)
        Rails.logger.info("[dns] manual DNS: proxy toggle (#{proxied}) for #{app_name} is a no-op (no DNS provider configured)")
        nil
      end
    end
  end
end

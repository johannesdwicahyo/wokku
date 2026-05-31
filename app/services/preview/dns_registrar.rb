module Preview
  class DnsRegistrar
    def initialize(preview_app)
      @preview_app = preview_app
    end

    def register
      subdomain = @preview_app.preview_subdomain
      hostname  = @preview_app.preview_hostname
      dns_client.create_app_record(subdomain, @preview_app.server.host)

      PreviewDnsRecord.find_or_create_by!(app_record: @preview_app) do |record|
        record.hostname = hostname
      end
    rescue ActiveRecord::RecordNotUnique
      PreviewDnsRecord.find_by(app_record: @preview_app)
    end

    def unregister
      record = PreviewDnsRecord.find_by(app_record: @preview_app)
      return unless record

      begin
        dns_client.delete_app_record(@preview_app.preview_subdomain)
      rescue StandardError => e
        Rails.logger.warn("Preview::DnsRegistrar.unregister: #{e.message}")
      end

      record.destroy!
    end

    private

    def dns_client
      @dns_client ||= Cloudflare::Dns.new
    end
  end
end

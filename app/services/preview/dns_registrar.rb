module Preview
  class DnsRegistrar
    def initialize(preview_app)
      @preview_app = preview_app
    end

    def register
      subdomain = @preview_app.preview_subdomain
      hostname  = @preview_app.preview_hostname
      Wokku.config.dns_provider.create_app_record(subdomain, @preview_app.server.host)

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
        # Every zone, not just the canonical one — the preview record may
        # predate a cutover and only exist in the legacy zone.
        Wokku.config.dns_provider.delete_app_record(@preview_app.preview_subdomain)
      rescue StandardError => e
        Rails.logger.warn("Preview::DnsRegistrar.unregister: #{e.message}")
      end

      record.destroy!
    end
  end
end

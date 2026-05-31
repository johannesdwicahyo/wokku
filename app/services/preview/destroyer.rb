module Preview
  class Destroyer
    def initialize(preview_app)
      @preview = preview_app
    end

    def call
      return unless @preview && AppRecord.exists?(@preview.id)

      Preview::DnsRegistrar.new(@preview).unregister

      begin
        client = Dokku::Client.new(@preview.server)
        Dokku::Apps.new(client).destroy(@preview.name)
      rescue Dokku::Client::CommandError => e
        Rails.logger.warn("Preview::Destroyer Dokku destroy failed: #{e.message}")
      end

      @preview.destroy!
    end
  end
end

class PrPreviewCleanupJob < ApplicationJob
  queue_as :deploys

  def perform(parent_app_id:, pr_number:)
    parent_app = AppRecord.find(parent_app_id)
    server = parent_app.server
    preview_name = "#{parent_app.name}-pr-#{pr_number}"

    app = AppRecord.find_by(name: preview_name, server: server)
    return unless app

    begin
      client = Dokku::Client.new(server)
      Dokku::Apps.new(client).destroy(preview_name)
    rescue Dokku::Client::CommandError => e
      Rails.logger.warn("PrPreviewCleanupJob: Dokku destroy failed: #{e.message}")
    end

    app.destroy!
    Rails.logger.info("PrPreviewCleanupJob: Cleaned up #{preview_name}")
  end
end

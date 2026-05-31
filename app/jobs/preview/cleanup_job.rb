module Preview
  class CleanupJob < ApplicationJob
    queue_as :default

    def perform(parent_app_id, pr_number)
      preview = AppRecord.previews.find_by(parent_app_id: parent_app_id, pr_number: pr_number)
      Preview::Destroyer.new(preview).call if preview
    end
  end
end

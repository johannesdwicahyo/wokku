module Api
  module V1
    module Agent
      # Serves deploy archives when the backup_store is the local
      # filesystem (self-host default) — the store can't presign, so the
      # claim endpoint hands the agent a URL to this action instead. The
      # short-lived signed token IS the auth (same contract as a presigned
      # GET), so this deliberately skips the agent bearer-token chain.
      class ArchivesController < ActionController::API
        def show
          deploy_id = Rails.application.message_verifier(:deploy_archive).verified(params[:token].to_s)
          return head :not_found unless deploy_id

          deploy = Deploy.find_by(id: deploy_id)
          store = Wokku.config.backup_store
          unless deploy&.archive_key.present? && store.respond_to?(:path) && store.exists?(deploy.archive_key)
            return head :not_found
          end

          send_file store.path(deploy.archive_key),
                    type: "application/gzip", disposition: "attachment", filename: "archive.tar.gz"
        end
      end
    end
  end
end

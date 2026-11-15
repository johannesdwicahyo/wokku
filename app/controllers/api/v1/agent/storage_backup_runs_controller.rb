module Api
  module V1
    module Agent
      # Nightly RustFS -> R2 backup reports from the host script. Same
      # per-server ingest_token trust boundary as the rest of the agent API.
      class StorageBackupRunsController < BaseController
        def create
          run = @server.storage_backup_runs.new(
            params.permit(:kind, :status, :objects, :bytes, :duration_s, :error)
          )
          if run.save
            render json: { id: run.id }, status: :created
          else
            render json: { errors: run.errors.full_messages }, status: :unprocessable_content
          end
        end
      end
    end
  end
end

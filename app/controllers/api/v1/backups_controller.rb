module Api
  module V1
    class BackupsController < BaseController
      def index
        db = policy_scope(DatabaseService).lookup!(params[:database_id])
        authorize db.server, :show?
        backups = db.backups.order(created_at: :desc)
        render json: backups.map { |b|
          { id: b.id, status: b.status, size_bytes: b.size_bytes, created_at: b.created_at }
        }
      end

      def create
        db = policy_scope(DatabaseService).lookup!(params[:database_id])
        authorize db.server, :update?

        if db.backups_unsupported?
          render json: { error: DatabaseService::BACKUPS_UNSUPPORTED_MESSAGE }, status: :unprocessable_entity
          return
        end

        if db.backup_limit_reached?
          render json: {
            error: "Free tier limit reached (2 backups). Upgrade to Basic for daily auto-backups with 7-day retention."
          }, status: :payment_required
          return
        end

        BackupJob.perform_later(db.id)
        render json: { message: "Backup started" }, status: :created
      rescue ActiveRecord::RecordNotFound, Pundit::NotAuthorizedError
        raise # handled by BaseController (404 / 403), not the generic 422 below
      rescue => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      def download
        db = policy_scope(DatabaseService).lookup!(params[:database_id])
        authorize db, :show?
        backup = db.backups.find(params[:id])
        render json: { url: backup.download_url(expires_in: 300), expires_in: 300 }
      end

      def restore
        db = policy_scope(DatabaseService).lookup!(params[:database_id])
        authorize db, :update?
        backup = db.backups.find(params[:id])

        RestoreService.new(backup).perform!
        render json: { message: "Restore completed", restored_to: db.name, from_backup: backup.id }
      rescue ActiveRecord::RecordNotFound, Pundit::NotAuthorizedError
        raise # handled by BaseController (404 / 403), not the generic 422 below
      rescue => e
        render json: { error: e.message }, status: :unprocessable_entity
      end
    end
  end
end

module Api
  module V1
    class BackupsController < BaseController
      def index
        db = DatabaseService.lookup!(params[:database_id])
        authorize db.server, :show?
        backups = db.backups.order(created_at: :desc)
        render json: backups.map { |b|
          { id: b.id, status: b.status, size_bytes: b.size_bytes, created_at: b.created_at }
        }
      end

      def create
        db = DatabaseService.lookup!(params[:database_id])
        authorize db.server, :update?

        if db.backup_limit_reached?
          render json: {
            error: "Free tier limit reached (2 backups). Upgrade to Basic for daily auto-backups with 7-day retention."
          }, status: :payment_required
          return
        end

        BackupJob.perform_later(db.id)
        render json: { message: "Backup started" }, status: :created
      rescue => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      def download
        db = DatabaseService.lookup!(params[:database_id])
        authorize db, :show?
        backup = db.backups.find(params[:id])
        render json: { url: backup.download_url(expires_in: 300), expires_in: 300 }
      end

      def restore
        db = DatabaseService.lookup!(params[:database_id])
        authorize db, :update?
        backup = db.backups.find(params[:id])

        RestoreService.new(backup).perform!
        render json: { message: "Restore completed", restored_to: db.name, from_backup: backup.id }
      rescue => e
        render json: { error: e.message }, status: :unprocessable_entity
      end
    end
  end
end

module Api
  module V1
    class BackupsController < BaseController
      def index
        db = DatabaseService.find(params[:database_id])
        authorize db.server, :show?
        backups = db.backups.order(created_at: :desc)
        render json: backups.map { |b|
          { id: b.id, status: b.status, size_bytes: b.size_bytes, created_at: b.created_at }
        }
      end

      def create
        db = DatabaseService.find(params[:database_id])
        authorize db.server, :update?
        backup = db.backups.create!(status: :pending)
        BackupJob.perform_later(backup.id)
        render json: { id: backup.id, status: "pending", message: "Backup started" }, status: :created
      rescue => e
        render json: { error: e.message }, status: :unprocessable_entity
      end
    end
  end
end

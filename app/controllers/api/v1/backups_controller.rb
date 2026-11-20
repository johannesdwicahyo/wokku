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
        authorize db, :update? # same rule as the dashboard (and #restore below)

        if db.backups_unsupported?
          render json: { error: db.backups_unsupported_message }, status: :unprocessable_entity
          return
        end

        if db.backup_limit_reached?
          render json: {
            error: db.backup_limit_message
          }, status: :payment_required
          return
        end

        BackupJob.perform_later(db.id)
        render json: { message: "Backup started" }, status: :created
      end

      def download
        db = policy_scope(DatabaseService).lookup!(params[:database_id])
        # A dump holds every secret: members+ on a full token, like config.
        raise Pundit::NotAuthorizedError unless reveal_secrets?(db)
        backup = db.backups.find(params[:id])
        render json: { url: backup.download_url(expires_in: 300), expires_in: 300 }
      end

      def restore
        db = policy_scope(DatabaseService).lookup!(params[:database_id])
        authorize db, :update?
        backup = db.backups.find(params[:id])

        # Async: a restore outlives the proxy's ~30 s response window.
        RestoreJob.perform_later(backup.id, current_user.id)
        render json: { message: "Restore started", restored_to: db.name, from_backup: backup.id }, status: :accepted
      rescue ActiveRecord::RecordNotFound, Pundit::NotAuthorizedError
        raise # handled by BaseController (404 / 403)
      rescue => e
        render_reported_error(:restore_failed, e)
      end
    end
  end
end

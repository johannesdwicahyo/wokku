module Dashboard
  class BackupsController < BaseController
    def index
      @database = DatabaseService.find(params[:addon_id])
      authorize @database, :show?
      @backups = @database.backups.order(created_at: :desc).limit(30)
      @destination = @database.server.backup_destination
    end

    def create
      @database = DatabaseService.find(params[:addon_id])
      authorize @database, :update?

      if @database.backups_unsupported?
        redirect_to dashboard_addon_backups_path(@database), alert: @database.backups_unsupported_message
        return
      end

      if @database.backup_limit_reached?
        redirect_to dashboard_addon_backups_path(@database),
          alert: @database.backup_limit_message
        return
      end

      BackupJob.perform_later(@database.id)
      redirect_to dashboard_addon_backups_path(@database), notice: "Backup started..."
    end

    def download
      backup = Backup.find(params[:id])
      authorize backup.database_service, :show?

      redirect_to backup.download_url(expires_in: 300), allow_other_host: true
    end

    def restore
      backup = Backup.find(params[:id])
      authorize backup.database_service, :update?

      RestoreJob.perform_later(backup.id, current_user.id)
      redirect_to dashboard_addon_backups_path(backup.database_service),
        notice: "Restore started. It runs in the background; the result shows in Activity."
    end
  end
end

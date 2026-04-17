module Dashboard
  class BackupsController < BaseController
    def index
      @database = DatabaseService.find(params[:resource_id])
      authorize @database, :show?
      @backups = @database.backups.order(created_at: :desc).limit(30)
      @destination = @database.server.backup_destination
    end

    def create
      @database = DatabaseService.find(params[:resource_id])
      authorize @database, :update?

      if @database.backup_limit_reached?
        redirect_to dashboard_resource_backups_path(@database),
          alert: "Free tier limit reached (2 backups). Upgrade to Basic for daily auto-backups with 7-day retention."
        return
      end

      BackupJob.perform_later(@database.id)
      redirect_to dashboard_resource_backups_path(@database), notice: "Backup started..."
    end

    def download
      backup = Backup.find(params[:id])
      authorize backup.database_service, :show?

      redirect_to backup.download_url(expires_in: 300), allow_other_host: true
    end

    def restore
      backup = Backup.find(params[:id])
      authorize backup.database_service, :update?

      begin
        RestoreService.new(backup).perform!
        redirect_to dashboard_resource_backups_path(backup.database_service), notice: "Restore completed"
      rescue => e
        redirect_to dashboard_resource_backups_path(backup.database_service), alert: "Restore failed: #{e.message}"
      end
    end
  end
end

module Dashboard
  class BackupDestinationsController < BaseController
    def edit
      @server = policy_scope(Server).find(params[:server_id])
      authorize @server, :update?
      @destination = @server.backup_destination || @server.build_backup_destination
    end

    def update
      @server = policy_scope(Server).find(params[:server_id])
      authorize @server, :update?
      @destination = @server.backup_destination || @server.build_backup_destination

      if @destination.update(destination_params)
        redirect_to dashboard_server_path(@server), notice: "Backup destination saved"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def destination_params
      params.require(:backup_destination).permit(
        :provider, :endpoint_url, :bucket, :region,
        :access_key_id, :secret_access_key, :path_prefix,
        :retention_days, :enabled
      )
    end
  end
end

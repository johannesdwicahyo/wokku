module Dashboard
  class BackupDestinationsController < BaseController
    def edit
      @server = policy_scope(Server).find(params[:server_id])
      authorize @server, :update?
      @destination = @server.backup_destination || @server.build_backup_destination(enabled: true, path_prefix: "dbs/#{@server.name.parameterize}")
    end

    def update
      @server = policy_scope(Server).find(params[:server_id])
      authorize @server, :update?
      @destination = @server.backup_destination || @server.build_backup_destination

      @destination.assign_attributes(destination_params)
      if @destination.valid? && connection_ok? && @destination.save
        redirect_to admin_server_path(@server), notice: "Backup destination saved"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def connection_ok?
      return true unless @destination.enabled?
      @destination.verify_connection!
      true
    rescue BackupDestination::ConnectionError => e
      @destination.errors.add(:base, e.message)
      false
    end

    def destination_params
      permitted = params.require(:backup_destination).permit(
        :provider, :endpoint_url, :bucket, :region,
        :access_key_id, :secret_access_key, :path_prefix,
        :retention_days, :enabled
      )
      # The secret field is never pre-filled; blank means "keep the stored one".
      permitted.delete(:secret_access_key) if permitted[:secret_access_key].blank? && @destination.persisted?
      permitted
    end
  end
end

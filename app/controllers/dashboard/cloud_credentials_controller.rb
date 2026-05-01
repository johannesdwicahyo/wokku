module Dashboard
  class CloudCredentialsController < BaseController
    def index
      @credentials = current_team.cloud_credentials
    end

    def create
      @credential = current_team.cloud_credentials.build(credential_params)
      if @credential.save
        redirect_to new_dashboard_server_path, notice: "#{@credential.provider.capitalize} connected"
      else
        redirect_to new_dashboard_server_path, alert: @credential.errors.full_messages.join(", ")
      end
    end

    def destroy
      credential = current_team.cloud_credentials.find(params[:id])
      credential.destroy
      redirect_to dashboard_servers_path, notice: "Cloud provider removed"
    end

    private

    def credential_params
      params.require(:cloud_credential).permit(:provider, :api_key, :name)
    end
  end
end

module Admin
  # Cloud-provider credentials (Hetzner / DigitalOcean / Linode / etc).
  # Admin-only because credentials provision servers across the whole
  # platform — they're not per-tenant. Pre-Phase-2 this lived under
  # Dashboard:: namespace but was already redirect-only with no view;
  # Phase 3 backlog #19 gave it a real /admin/cloud_credentials home.
  class CloudCredentialsController < BaseController
    def index
      @credentials = CloudCredential.order(:provider, :name).includes(:team)
    end

    def create
      # current_team comes from Admin::BaseController; admin creates the
      # credential under their own team. Tenant ownership isn't load-
      # bearing here — admin can use any credential across servers.
      @credential = current_team.cloud_credentials.build(credential_params)
      if @credential.save
        redirect_to new_admin_server_path, notice: "#{@credential.provider.capitalize} connected"
      else
        redirect_to new_admin_server_path, alert: @credential.errors.full_messages.join(", ")
      end
    end

    def destroy
      credential = CloudCredential.find(params[:id])
      credential.destroy
      redirect_to admin_cloud_credentials_path, notice: "Cloud provider removed"
    end

    private

    def credential_params
      params.require(:cloud_credential).permit(:provider, :api_key, :name)
    end
  end
end

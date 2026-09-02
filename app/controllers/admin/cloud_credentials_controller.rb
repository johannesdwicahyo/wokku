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
      # Two callers post here: the index slide-panel (params[:after] ==
      # "index") and the server-new inline form (after: "server", or no
      # param at all — the pre-slide-panel default). Explicit param, not
      # request.referer (brittle) — see task-4 brief.
      redirect_target = params[:after] == "index" ? admin_cloud_credentials_path : new_admin_server_path
      if @credential.save
        redirect_to redirect_target, notice: "#{@credential.provider.capitalize} connected"
      else
        redirect_to redirect_target, alert: @credential.errors.full_messages.join(", ")
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

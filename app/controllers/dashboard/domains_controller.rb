module Dashboard
  class DomainsController < BaseController
    before_action :set_app

    def index
      authorize @app, :show?
      @domains = @app.domains
    end

    def create
      authorize @app, :update?
      @domain = @app.domains.build(domain_params)

      if @domain.save
        # Add domain on the Dokku server
        client = Dokku::Client.new(@app.server)
        Dokku::Domains.new(client).add(@app.name, @domain.hostname)
        track("domain.added", target: @domain, metadata: { app: @app.name, hostname: @domain.hostname })
        # Auto-verify DNS + auto-enable Let's Encrypt once the A/CNAME
        # resolves to our IP. Without this users add a domain, see no
        # SSL, and hit ERR_CERT_COMMON_NAME_INVALID — caught a real
        # case during smoke testing.
        DnsVerificationJob.perform_later(@domain.id)
        redirect_to dashboard_app_domains_path(@app), notice: "Domain added. SSL will be enabled automatically once DNS resolves."
      else
        @domains = @app.domains.reload
        render :index, status: :unprocessable_entity
      end
    end

    def ssl
      authorize @app, :update?
      domain = @app.domains.find(params[:id])
      domain.update(pending_action: "ssl_enable")
      EnableSslJob.perform_later(domain.id)
      track("domain.ssl_queued", target: domain, metadata: { app: @app.name, hostname: domain.hostname })
      redirect_to dashboard_app_domains_path(@app)
    end

    def destroy
      authorize @app, :update?
      domain = @app.domains.find(params[:id])

      # Remove domain from the Dokku server
      client = Dokku::Client.new(@app.server)
      Dokku::Domains.new(client).remove(@app.name, domain.hostname)

      hostname = domain.hostname
      domain.destroy
      track("domain.removed", target: @app, metadata: { app: @app.name, hostname: hostname })
      redirect_to dashboard_app_domains_path(@app), notice: "Domain removed successfully."
    end

    private

    def set_app
      @app = AppRecord.find(params[:app_id])
    end

    def domain_params
      params.require(:domain).permit(:hostname)
    end
  end
end

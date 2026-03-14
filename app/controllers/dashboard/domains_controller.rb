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
        redirect_to dashboard_app_domains_path(@app), notice: "Domain added successfully."
      else
        @domains = @app.domains
        render :index, status: :unprocessable_entity
      end
    end

    def ssl
      authorize @app, :update?
      domain = @app.domains.find(params[:id])

      client = Dokku::Client.new(@app.server)
      Dokku::Domains.new(client).enable_ssl(@app.name)
      domain.update!(ssl_enabled: true)
      domain.create_certificate!(auto_renew: true, expires_at: 90.days.from_now) unless domain.certificate

      redirect_to dashboard_app_domains_path(@app), notice: "SSL enabled for #{domain.hostname}."
    rescue => e
      redirect_to dashboard_app_domains_path(@app), alert: "SSL failed: #{e.message}"
    end

    def destroy
      authorize @app, :update?
      domain = @app.domains.find(params[:id])

      # Remove domain from the Dokku server
      client = Dokku::Client.new(@app.server)
      Dokku::Domains.new(client).remove(@app.name, domain.hostname)

      domain.destroy
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

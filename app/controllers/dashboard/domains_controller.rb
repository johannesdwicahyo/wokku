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
        redirect_to dashboard_app_domains_path(@app), notice: "Domain added successfully."
      else
        @domains = @app.domains
        render :index, status: :unprocessable_entity
      end
    end

    def destroy
      authorize @app, :update?
      domain = @app.domains.find(params[:id])
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

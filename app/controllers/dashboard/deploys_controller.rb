module Dashboard
  class DeploysController < BaseController
    def show
      @app = policy_scope(AppRecord).find(params[:app_id])
      authorize @app, :show?
      @deploy = @app.deploys.find(params[:id])
    end
  end
end

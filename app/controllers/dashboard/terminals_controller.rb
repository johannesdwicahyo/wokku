module Dashboard
  class TerminalsController < BaseController
    def show
      @server = policy_scope(Server).find(params[:server_id])
      authorize @server, :show?
      @app = AppRecord.find_by(id: params[:app_id]) if params[:app_id]
    end
  end
end

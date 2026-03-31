module Dashboard
  class TerminalsController < BaseController
    def show
      if params[:app_id]
        @app = AppRecord.find(params[:app_id])
        @server = @app.server
      else
        @server = policy_scope(Server).find(params[:server_id])
      end
      authorize @server, :show?
    end
  end
end

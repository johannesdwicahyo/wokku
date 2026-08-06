module Dashboard
  class ChecksController < BaseController
    before_action :set_app

    def show
      authorize @app, :show?

      return render_deferred_fragment if params[:deferred]

      # Shell branch: no SSH — renders instantly via show.html.erb.
      @app
    end

    def update
      authorize @app, :update?

      # Apps run on Swarm — container healthchecks land with the wokkud
      # agent batch.
      redirect_to dashboard_app_checks_path(@app),
        alert: "Health checks for this app are managed by the Swarm runtime — configurable healthchecks are coming soon."
    rescue => e
      redirect_to dashboard_app_checks_path(@app), alert: "Failed to update checks: #{e.message}"
    end

    private

    def render_deferred_fragment
      @checks = {}
      flash.now[:notice] = "This app runs on the Swarm runtime — health is supervised by the platform (start-first rotates, automatic restarts)."
      render partial: "dashboard/checks/frame", layout: false
    end

    def set_app
      @app = AppRecord.find(params[:app_id])
    end
  end
end

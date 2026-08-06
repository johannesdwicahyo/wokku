module Api
  module V1
    # Poll surface for stack.run ops. POST lives on AppsController#run
    # (existing legacy `dokku run` route — apps#run branches on
    # wokkud_lifecycle? the same way DokkuAppActionJob does for
    # restart/stop/start) since kamal-proxy caps responses at 30s and a
    # one-off command needs the async 202 + run_id contract; this
    # controller is the GET-only follow-up clients poll for status.
    class RunsController < BaseController
      def show
        app = AppRecord.lookup!(params[:app_id])
        authorize app, :show?
        op = app.lifecycle_ops.find_by(id: params[:id], kind: "stack.run")
        return render_api_error(:not_found, message: "run not found") unless op

        render json: {
          run_id: op.id, status: op.status,
          exit_code: op.result&.dig("exit_code"),
          output: op.result&.dig("output"),
          error: op.error, error_code: op.error_code
        }
      end
    end
  end
end

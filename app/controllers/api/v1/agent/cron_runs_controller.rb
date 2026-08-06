module Api
  module V1
    module Agent
      # Track B B3: wokkud batch-reports cron run results here after each
      # heartbeat cycle. Ingest is scoped to @server (BaseController's
      # ingest_token auth) — Cron::RunRecorder further scopes each row's
      # task lookup to apps on that server, so a stolen token from one
      # server can't inject run history for another server's tasks.
      class CronRunsController < BaseController
        def create
          rows = params.permit(runs: [ :task_id, :started_at, :finished_at, :exit_code, :skipped_reason, :log_excerpt ])[:runs] || []
          render json: { recorded: Cron::RunRecorder.new(@server).call(rows.map(&:to_h)) }
        end
      end
    end
  end
end

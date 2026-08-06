module Api
  module V1
    module Agent
      # Datastore-op endpoints (Track B Phase B4). Mirrors BuildsController's
      # trust boundary and refusal semantics: strict server scoping (404),
      # atomic single claim (409), terminal ops are sealed (410).
      class ServiceOpsController < BaseController
        # B4 gate 7: per-kind agent timeouts. The original flat 300s killed
        # large export/import streams the legacy SSH path allowed 600s+ for;
        # create pulls a cold image on first use of an engine version.
        KIND_TIMEOUT_SECONDS = Hash.new(300).merge(
          "service.export" => 900,
          "service.import" => 900,
          "service.create" => 600
        ).freeze

        # B4 gate 2: params carry secrets (DB password, presigned R2 URLs)
        # needed by the agent DURING the op — once the op is terminal they
        # are dead weight at rest. Redacted on report; 30-day prune in
        # ServiceOpJanitorJob removes the rest of the row.
        SECRET_PARAM_KEYS = %w[password presigned_put_url presigned_get_url dek].freeze

        before_action :set_op

        def claim
          claimed = ServiceOp.where(id: @op.id, status: :pending)
                             .update_all(status: :claimed, claimed_at: Time.current) == 1
          return head :conflict unless claimed

          render json: {
            id: @op.id,
            kind: @op.kind,
            service: @op.database_service.container_name,
            params: @op.params,
            timeout_seconds: KIND_TIMEOUT_SECONDS[@op.kind]
          }
        end

        def log
          chunk = params[:chunk].to_s
          return head :bad_request if chunk.empty?
          ServiceOp.where(id: @op.id).update_all([ "log = COALESCE(log, '') || ?", chunk ])
          head :ok
        end

        def report
          if params[:status] == "succeeded"
            @op.update!(status: :succeeded, finished_at: Time.current,
                        result: params[:result].respond_to?(:to_unsafe_h) ? params[:result].to_unsafe_h : params[:result])
          else
            @op.update!(status: :failed, finished_at: Time.current,
                        error: params[:error].presence || "op failed",
                        error_code: params[:error_code].presence)
          end
          redact_secret_params!
          head :ok
        end

        private

        def redact_secret_params!
          redacted = @op.params.to_h.map { |k, v| [ k, SECRET_PARAM_KEYS.include?(k.to_s) ? "[REDACTED]" : v ] }.to_h
          @op.update_column(:params, redacted) if redacted != @op.params
        end

        def set_op
          @op = ServiceOp.find_by(id: params[:id], server_id: @server.id)
          return head :not_found unless @op
          # Late/duplicate reports 410: agent treats as already-settled, stops retrying.
          head :gone if @op.terminal?
        end
      end
    end
  end
end

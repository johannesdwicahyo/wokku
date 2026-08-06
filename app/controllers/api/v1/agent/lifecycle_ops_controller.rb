module Api
  module V1
    module Agent
      # Swarm lifecycle-op endpoints (Track B Phase B5a). Mirrors
      # ServiceOpsController's trust boundary and refusal semantics verbatim:
      # strict server scoping (404), atomic single claim (409), terminal ops
      # are sealed (410).
      class LifecycleOpsController < BaseController
        # B5a: per-kind agent timeouts. stack.converge pulls images and
        # reconciles the whole app formation — headroom above the flat 300s
        # stack.remove (a teardown) is fine with.
        KIND_TIMEOUT_SECONDS = Hash.new(300).merge("stack.converge" => 600, "stack.run" => 600).freeze

        # B5a: params carry the app's env during the op — dead weight at
        # rest once terminal. Redacted on report, mirroring B4 gate 2.
        # `command` too: Lifecycle::Ops.run! bakes $VAR env values INTO the
        # command string (e.g. a DSN), so it carries the same secrets.
        SECRET_PARAM_KEYS = %w[env command].freeze

        before_action :set_op

        def claim
          claimed = LifecycleOp.where(id: @op.id, status: :pending)
                               .update_all(status: :claimed, claimed_at: Time.current) == 1
          return head :conflict unless claimed

          render json: {
            id: @op.id,
            kind: @op.kind,
            app_name: @op.app_record.name,
            params: @op.params,
            timeout_seconds: KIND_TIMEOUT_SECONDS[@op.kind]
          }
        end

        def log
          chunk = params[:chunk].to_s
          return head :bad_request if chunk.empty?
          LifecycleOp.where(id: @op.id).update_all([ "log = COALESCE(log, '') || ?", chunk ])
          head :ok
        end

        def report
          if params[:status] == "succeeded"
            @op.update!(status: :succeeded, finished_at: Time.current,
                        result: params[:result].respond_to?(:to_unsafe_h) ? params[:result].to_unsafe_h : params[:result])
          else
            @op.update!(status: :failed, finished_at: Time.current,
                        error: params[:error].presence || "op failed",
                        error_code: params[:error_code].presence,
                        result: params[:result].respond_to?(:to_unsafe_h) ? params[:result].to_unsafe_h : params[:result])
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
          @op = LifecycleOp.find_by(id: params[:id], server_id: @server.id)
          return head :not_found unless @op
          # Late/duplicate reports 410: agent treats as already-settled, stops retrying.
          head :gone if @op.terminal?
        end
      end
    end
  end
end

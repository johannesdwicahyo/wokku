module Api
  module V1
    class DevSessionsController < BaseController
      before_action :set_app

      def create
        authorize @app, :update?

        duration = params[:duration_min].to_i
        session = ::Apps::DevSession::Issuer.new(app: @app, user: current_user).call!(
          duration_min: duration.positive? ? duration : 30
        )

        Activity.log(user: current_user, team: @app.team, action: "app.dev_session_created", target: @app,
                     metadata: { session_id: session.id, expires_at: session.expires_at })

        render json: {
          session_id: session.id,
          ssh_host: @app.server.host,
          ssh_port: 22,
          ssh_user: "dev",
          ssh_principal: session.ssh_principal,
          db_remote_host: session.db_remote_host,
          db_remote_port: session.db_remote_port,
          local_port_suggestion: 5433,
          readonly: session.read_only,
          expires_at: session.expires_at
        }, status: :created
      rescue ::Apps::DevSession::Error => e
        render_api_error(ApiErrors.from_service_code(e.code), message: e.message)
      end

      def destroy
        authorize @app, :update?

        session = ::DevSession.find_by(id: params[:id], app_record_id: @app.id, user_id: current_user.id)
        return head :no_content if session.nil? # idempotent

        ::Apps::DevSession::Revoker.new(session).call!
        Activity.log(user: current_user, team: @app.team, action: "app.dev_session_revoked", target: @app,
                     metadata: { session_id: session.id })
        head :no_content
      rescue ::Apps::DevSession::Error => e
        render_api_error(ApiErrors.from_service_code(e.code), message: e.message)
      end

      private

      def set_app
        @app = AppRecord.lookup!(params[:app_id])
      end
    end
  end
end

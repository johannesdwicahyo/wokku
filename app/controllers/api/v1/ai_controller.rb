module Api
  module V1
    class AiController < BaseController
      def diagnose
        deploy = Deploy.where(app_record: policy_scope(AppRecord)).find(params[:deploy_id])
        authorize deploy.app_record, :show?

        debugger = AiDebugger.new(deploy)
        result = debugger.diagnose

        if result[:error]
          Rails.logger.warn("[api] ai.diagnose #{deploy.id}: #{result[:error_code]}")
          return render_api_error(result[:error_code])
        end

        render json: result
      end
    end
  end
end

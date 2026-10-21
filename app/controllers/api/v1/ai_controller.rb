module Api
  module V1
    class AiController < BaseController
      # AiDebugger signals failure in-band with { error: "..." }.
      AI_ERROR_CODES = {
        "No API key configured" => :ai_unavailable,
        "No deploy log available" => :no_deploy_log
      }.freeze

      def diagnose
        deploy = Deploy.where(app_record: policy_scope(AppRecord)).find(params[:deploy_id])
        authorize deploy.app_record, :show?

        debugger = AiDebugger.new(deploy)
        result = debugger.diagnose

        if result[:error]
          Rails.logger.warn("[api] ai.diagnose #{deploy.id}: #{result[:error]}")
          return render_api_error(AI_ERROR_CODES.fetch(result[:error]) { result[:error].start_with?("AI diagnosis failed") ? :ai_provider_failed : :internal_error })
        end

        render json: result
      end
    end
  end
end

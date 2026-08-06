module Api
  module V1
    class AiController < BaseController
      def diagnose
        deploy = Deploy.find(params[:deploy_id])
        authorize deploy.app_record, :show?

        debugger = AiDebugger.new(deploy)
        result = debugger.diagnose

        render json: result
      end
    end
  end
end

module Dashboard
  class AiController < BaseController
    def diagnose
      @deploy = Deploy.find(params[:deploy_id])
      authorize @deploy.app_record, :show?

      debugger = AiDebugger.new(@deploy)
      @result = debugger.diagnose

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update(
            "ai-diagnosis",
            partial: "dashboard/ai/diagnosis",
            locals: { result: @result }
          )
        end
        format.html { redirect_to dashboard_app_deploy_path(@deploy.app_record, @deploy) }
      end
    end
  end
end

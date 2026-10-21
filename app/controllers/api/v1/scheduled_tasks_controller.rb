module Api
  module V1
    class ScheduledTasksController < BaseController
      before_action :set_app

      def index
        authorize @app, :show?
        tasks = @app.scheduled_tasks.order(:schedule).map { |t| ::Api::V1::Serializers::ScheduledTask.new(t).call }
        render json: tasks
      end

      def create
        authorize @app, :update?

        unless Wokku.config.plan_enforcer.allowed?(current_user, :feature, slug: :scheduled_tasks)
          return render json: { error: "Upgrade to Pro to use Scheduled Tasks", upgrade_url: "/dashboard/plan" }, status: :forbidden
        end

        task = ::Apps::Cron::TaskCreator.new(@app).call!(
          command: params[:command].to_s,
          schedule: params[:schedule].to_s,
          description: params[:description]
        )
        Activity.log(user: current_user, team: @app.team, action: "app.scheduled_task_added", target: @app,
                     metadata: { schedule: task.schedule })
        render json: ::Api::V1::Serializers::ScheduledTask.new(task).call, status: :created
      rescue ::Apps::Cron::Error => e
        render_api_error(ApiErrors.from_service_code(e.code), message: e.message)
      end

      def destroy
        authorize @app, :update?

        task = @app.scheduled_tasks.find_by(id: params[:id])
        return render_api_error(:not_found, message: "Scheduled task not found") unless task

        ::Apps::Cron::TaskDestroyer.new(@app).call!(task)
        Activity.log(user: current_user, team: @app.team, action: "app.scheduled_task_removed", target: @app,
                     metadata: { task_id: task.id })
        head :no_content
      rescue ::Apps::Cron::Error => e
        render_api_error(ApiErrors.from_service_code(e.code), message: e.message)
      end

      private

      def set_app
        @app = policy_scope(AppRecord).lookup!(params[:app_id])
      end
    end
  end
end

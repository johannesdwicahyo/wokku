module Dashboard
  # ScheduledTasks — Pro-tier feature (per spec §2). Lets the app owner
  # define cron entries from the dashboard. Changes are written to the
  # on-host app.json by Dokku::ScheduledTasks and a rebuild is
  # triggered so the Dokku cron plugin re-registers.
  class ScheduledTasksController < BaseController
    before_action :set_app
    before_action :require_pro_feature, except: [ :index ]

    def index
      @tasks = @app.scheduled_tasks.order(:schedule)
      # Pre-populate for the inline slide-panel "+ new" modal.
      @new_task = @app.scheduled_tasks.new
    end

    def new
      @task = @app.scheduled_tasks.new
    end

    def create
      @task = @app.scheduled_tasks.new(task_params)
      if @task.save
        Dokku::ScheduledTasks.new(@app).sync!
        redirect_to dashboard_app_scheduled_tasks_path(@app),
          notice: "Scheduled task added."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def destroy
      @task = @app.scheduled_tasks.find(params[:id])
      @task.destroy!
      Dokku::ScheduledTasks.new(@app).sync!
      redirect_to dashboard_app_scheduled_tasks_path(@app),
        notice: "Scheduled task removed."
    end

    private

    def set_app
      @app = AppRecord.find(params[:app_id])
      authorize @app, :show?
    end

    def require_pro_feature
      return if current_user.plan&.has_feature?(:scheduled_tasks)
      redirect_to dashboard_app_path(@app),
        alert: "Upgrade to Pro to use Scheduled Tasks."
    end

    def task_params
      params.require(:scheduled_task).permit(:command, :schedule, :description, :enabled)
    end
  end
end

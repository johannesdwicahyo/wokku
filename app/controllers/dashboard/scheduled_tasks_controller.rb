module Dashboard
  # ScheduledTasks — Pro-tier feature (per spec §2). Lets the app owner
  # define cron entries from the dashboard. Cron truth lives in the
  # ScheduledTask rows, which wokkud fetches and registers on the host.
  class ScheduledTasksController < BaseController
    before_action :set_app
    before_action :require_pro_feature, except: [ :index ]

    def index
      @tasks = @app.scheduled_tasks.order(:schedule)
      @recent_runs = ScheduledTaskRun.where(scheduled_task: @tasks)
        .order(started_at: :desc)
        .limit(10 * @tasks.length)
        .group_by(&:scheduled_task_id)
      # Pre-populate for the inline slide-panel "+ new" modal.
      @new_task = @app.scheduled_tasks.new
    end

    def new
      @task = @app.scheduled_tasks.new
    end

    def create
      authorize @app, :update? # cron runs commands in the app — member+, as the API
      @task = ::Apps::Cron::TaskCreator.new(@app).call!(
        command: task_params[:command].to_s,
        schedule: task_params[:schedule].to_s,
        description: task_params[:description]
      )
      redirect_to dashboard_app_scheduled_tasks_path(@app), notice: "Scheduled task added."
    rescue ::Apps::Cron::Error => e
      @new_task = @app.scheduled_tasks.new(task_params)
      @new_task.errors.add(:base, e.message)
      @tasks = @app.scheduled_tasks.order(:schedule)
      render :index, status: :unprocessable_entity
    end

    def destroy
      authorize @app, :update?
      @task = @app.scheduled_tasks.find(params[:id])
      ::Apps::Cron::TaskDestroyer.new(@app).call!(@task)
      redirect_to dashboard_app_scheduled_tasks_path(@app), notice: "Scheduled task removed."
    rescue ::Apps::Cron::Error => e
      redirect_to dashboard_app_scheduled_tasks_path(@app), alert: "Couldn't remove: #{e.message}"
    end

    private

    def set_app
      @app = AppRecord.find(params[:app_id])
      authorize @app, :show?
    end

    def require_pro_feature
      return if Wokku.config.plan_enforcer.allowed?(current_user, :feature, slug: :scheduled_tasks)
      redirect_to dashboard_app_path(@app),
        alert: "Upgrade to Pro to use Scheduled Tasks."
    end

    def task_params
      params.require(:scheduled_task).permit(:command, :schedule, :description, :enabled)
    end
  end
end

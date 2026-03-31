module Dashboard
  class DashboardController < BaseController
    def show
      @apps = policy_scope(AppRecord).includes(:server, :domains).order(updated_at: :desc)
      @recent_apps = @apps.limit(6)
      @activities = Activity.where(team: current_team).order(created_at: :desc).limit(10)
      @servers = policy_scope(Server)

      @stats = {
        total_apps: @apps.size,
        active: @apps.select(&:running?).size,
        errors: @apps.select(&:crashed?).size
      }
    end
  end
end

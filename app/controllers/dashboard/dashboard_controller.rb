module Dashboard
  class DashboardController < BaseController
    def show
      @apps = policy_scope(AppRecord).includes(:server, :domains).order(updated_at: :desc)
      @recent_apps = @apps.limit(6)
      @activities = Activity.where(team: current_team).order(created_at: :desc).limit(10)
      @servers = policy_scope(Server)

      # Calculate estimated monthly cost from dyno allocations
      cost = 0.0
      if defined?(DynoAllocation)
        DynoAllocation.includes(:dyno_tier).find_each do |a|
          cost += a.dyno_tier.monthly_price_dollars * a.count rescue 0
        end
      end

      @stats = {
        total_apps: @apps.size,
        active: @apps.select(&:running?).size,
        errors: @apps.select(&:crashed?).size,
        cost_mtd: cost
      }
    end
  end
end

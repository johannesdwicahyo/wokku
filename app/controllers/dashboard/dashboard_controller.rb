module Dashboard
  class DashboardController < BaseController
    def show
      @apps = policy_scope(AppRecord).includes(:server, :domains).order(updated_at: :desc)
      @recent_apps = @apps.limit(6)
      # Collapse consecutive same-action+same-target runs into a single row
      # with a count badge. Without this a chatty deploy session crowds out
      # everything else in the 10-row window.
      raw_activities = Activity.where(team: current_team).order(created_at: :desc).limit(50)
      @activities = []
      raw_activities.each do |a|
        last = @activities.last
        if last && last.action == a.action && last.target_type == a.target_type && last.target_id == a.target_id
          last.singleton_class.attr_accessor :grouped_count unless last.respond_to?(:grouped_count)
          last.grouped_count = (last.grouped_count || 1) + 1
        else
          @activities << a
        end
        break if @activities.size >= 10
      end
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

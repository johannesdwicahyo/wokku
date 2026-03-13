module PlanEnforceable
  extend ActiveSupport::Concern

  private

  def enforce_app_limit!
    plan = current_user.current_plan
    return unless plan

    current_count = policy_scope(AppRecord).count
    if current_count >= plan.max_apps
      render json: { error: "App limit reached. Upgrade your plan.", upgrade_url: "/billing" }, status: :payment_required
    end
  end

  def enforce_database_limit!
    plan = current_user.current_plan
    return unless plan

    current_count = DatabaseService.joins(server: { team: :team_memberships })
      .where(team_memberships: { user_id: current_user.id }).count
    if current_count >= plan.max_databases
      render json: { error: "Database limit reached. Upgrade your plan.", upgrade_url: "/billing" }, status: :payment_required
    end
  end
end

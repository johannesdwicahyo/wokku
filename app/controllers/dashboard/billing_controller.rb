module Dashboard
  class BillingController < BaseController
    def show
      @plan = current_user.current_plan
      @subscription = current_user.subscriptions.current.first
      @plans = Plan.order(:price_cents_per_month)
      @app_count = policy_scope(AppRecord).count
      @db_count = policy_scope(DatabaseService).count
    end
  end
end

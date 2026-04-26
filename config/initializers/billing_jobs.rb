Rails.application.config.after_initialize do
  if defined?(SolidQueue) && SolidQueue.respond_to?(:recurring_schedule=)
    recurring = (SolidQueue.recurring_schedule || {}).dup
    recurring["billing_cycle"] = {
      "class" => "BillingCycleJob",
      "schedule" => "every month on the 1st at 2am",
      "queue" => "billing"
    }
    recurring["payment_failure_check"] = {
      "class" => "PaymentFailureJob",
      "schedule" => "every day at 6am",
      "queue" => "billing"
    }
    recurring["daily_usage_deduction"] = {
      "class" => "DailyUsageDeductionJob",
      "schedule" => "0 17 * * *",
      "queue" => "billing"
    }
    recurring["balance_check"] = {
      "class" => "BalanceCheckJob",
      "schedule" => "0 * * * *",
      "queue" => "billing"
    }
    SolidQueue.recurring_schedule = recurring
  end
end

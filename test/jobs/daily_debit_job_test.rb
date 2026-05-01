require "test_helper"

class DailyDebitJobTest < ActiveJob::TestCase
  setup do
    @user = User.create!(email: "daily-debit@example.com", password: "password123456", currency: "idr", balance_idr: 100_000)
    @team = Team.create!(name: "Debit", owner: @user)
    TeamMembership.create!(user: @user, team: @team, role: :admin)
  end

  test "no-ops when user id unknown" do
    assert_nothing_raised { DailyDebitJob.perform_now(-1) }
  end

  test "no-ops when Billing::DailyDeduction returns nil (no usage)" do
    Billing::DailyDeduction.any_instance.stubs(:process!).returns(nil)
    assert_no_difference "Activity.count" do
      DailyDebitJob.perform_now(@user.id)
    end
  end

  test "logs a billing.daily_debit activity when usage was charged" do
    record = { amount: 5_000, currency: "idr", date: Date.yesterday, breakdown: { "dyno:1" => 5_000 } }
    Billing::DailyDeduction.any_instance.stubs(:process!).returns(record)

    assert_difference "Activity.count", 1 do
      DailyDebitJob.perform_now(@user.id)
    end
    entry = Activity.last
    assert_equal "billing.daily_debit", entry.action
    assert_equal "system", entry.metadata["channel"]
    assert_equal 5_000, entry.metadata["amount"]
  end

  test "logs app_suspended activity when balance falls to zero" do
    record = { amount: 100_000, currency: "idr", date: Date.yesterday, breakdown: {} }
    Billing::DailyDeduction.any_instance.stubs(:process!).returns(record)
    # Simulate: balance already drained + marked suspended by DailyDeduction
    @user.update_columns(balance_idr: 0, billing_status: User.billing_statuses[:suspended])

    assert_difference "Activity.count", 2 do
      DailyDebitJob.perform_now(@user.id)
    end
    assert_equal %w[billing.app_suspended billing.daily_debit], Activity.last(2).map(&:action).sort
  end

  test "swallows exceptions so one bad user doesn't block the scheduler" do
    Billing::DailyDeduction.any_instance.stubs(:process!).raises(StandardError, "boom")
    assert_nothing_raised { DailyDebitJob.perform_now(@user.id) }
  end
end

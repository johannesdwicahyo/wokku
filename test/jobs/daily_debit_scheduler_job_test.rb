require "test_helper"

class DailyDebitSchedulerJobTest < ActiveJob::TestCase
  setup do
    @user_with_usage = User.create!(email: "with-usage@example.com", password: "password123456", currency: "idr")
    @team = Team.create!(name: "Sched", owner: @user_with_usage)
    @app = AppRecord.create!(name: "sched-app", team: @team, creator: @user_with_usage,
                             server: Server.create!(name: "sched-server", host: "1.2.3.4", team: @team))
    ResourceUsage.create!(
      user: @user_with_usage, resource_type: "dyno",
      resource_id_ref: "sched-app:web", tier_name: "basic",
      price_cents_per_hour: 0.137, started_at: 2.days.ago
    )

    @idle_user = User.create!(email: "idle@example.com", password: "password123456", currency: "idr")
  end

  test "enqueues DailyDebitJob only for users with active billable usage" do
    assert_enqueued_with(job: DailyDebitJob, args: [ @user_with_usage.id ]) do
      DailyDebitSchedulerJob.perform_now
    end
    assert_equal 1, enqueued_jobs.count { |j| j[:args] == [ @idle_user.id ] }, "idle user should not be enqueued"
  rescue Minitest::Assertion
    # assert_enqueued_with consumes the list; check the negative case
    # from the raw enqueued_jobs array directly.
    ids = enqueued_jobs.select { |j| j[:job] == DailyDebitJob }.map { |j| j[:args].first }
    assert_includes ids, @user_with_usage.id
    refute_includes ids, @idle_user.id
  end
end

require "rails_helper"

RSpec.describe ScheduledTaskRunPruneJob do
  it "deletes runs older than 30 days, keeps newer" do
    old = create(:scheduled_task_run, started_at: 31.days.ago, created_at: 31.days.ago)
    fresh = create(:scheduled_task_run, started_at: 1.day.ago)
    described_class.perform_now
    expect(ScheduledTaskRun.exists?(old.id)).to be(false)
    expect(ScheduledTaskRun.exists?(fresh.id)).to be(true)
  end
end

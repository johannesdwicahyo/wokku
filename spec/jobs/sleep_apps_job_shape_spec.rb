# NOTE: there is no SleepAppsJob in this codebase — IdleCheckJob is the real
# job that auto-sleeps idle apps (eco tier only). Substituted per task-4
# brief's guidance to use the real class rather than inventing one.
require "rails_helper"

RSpec.describe IdleCheckJob do
  it "never sleeps a shape-only (paid) app" do
    app = create(:app_record)
    app.dyno_allocations.create!(process_type: "web", count: 1, cpu: 0.25, memory_mb: 256)
    expect(DynoAllocation.find_by(app_record: app)).not_to be_sleeping
    expect { described_class.perform_now }.not_to raise_error
    expect(app.reload.sleeping?).to be_falsey
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe UptimeCheckSchedulerJob, type: :job do
  it "enqueues one UptimeCheckJob per running app with a domain" do
    with_domain = create(:app_record, status: :running)
    create(:domain, app_record: with_domain, hostname: "a1.wokku.app")
    create(:app_record, status: :running) # domainless — skipped
    stopped = create(:app_record, status: :stopped)
    create(:domain, app_record: stopped, hostname: "a2.wokku.app")

    expect { described_class.perform_now }
      .to have_enqueued_job(UptimeCheckJob).with(with_domain.id).exactly(:once)
  end

  it "skips the tick when saturated" do
    app = create(:app_record, status: :running)
    create(:domain, app_record: app, hostname: "a3.wokku.app")
    allow_any_instance_of(described_class).to receive(:scheduler_saturated?).and_return(true)
    expect { described_class.perform_now }.not_to have_enqueued_job(UptimeCheckJob)
  end

  it "does not probe sleeping-tier apps (probes would keep them awake)" do
    free = create(:app_record, status: :running)
    free.dyno_allocations.create!(process_type: "web", count: 1, dyno_tier: create(:dyno_tier, name: "free-u", sleeps: true))
    create(:domain, app_record: free, hostname: "free-u.wokku.app")
    expect { described_class.perform_now }.not_to have_enqueued_job(UptimeCheckJob).with(free.id)
  end

  it "still probes a shaped (paid) allocation on a sleeping tier" do
    paid = create(:app_record, status: :running)
    paid.dyno_allocations.create!(process_type: "web", count: 1, dyno_tier: create(:dyno_tier, name: "free-p", sleeps: true), cpu: 0.5, memory_mb: 512)
    create(:domain, app_record: paid, hostname: "paid-p.wokku.app")
    expect { described_class.perform_now }.to have_enqueued_job(UptimeCheckJob).with(paid.id)
  end
end

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
end

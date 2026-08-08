# frozen_string_literal: true

require "rails_helper"

RSpec.describe MetricsPollSchedulerJob, type: :job do
  let!(:server) { servers(:one) }

  it "enqueues a MetricsPollJob per server" do
    expect { described_class.perform_now }
      .to have_enqueued_job(MetricsPollJob).with(server.id)
  end

  it "skips the tick when too many polls are genuinely in flight" do
    # cap = max(servers*3, 10). With 1 server that's 10. 10 unfinished,
    # NON-failed (genuinely queued) jobs should trip the guard.
    10.times do
      SolidQueue::Job.create!(
        queue_name: "metrics", class_name: "MetricsPollJob",
        arguments: { arguments: [ server.id ] }.to_json, finished_at: nil
      )
    end

    expect { described_class.perform_now }.not_to have_enqueued_job(MetricsPollJob)
  end

  it "does NOT count failed executions toward the pending cap" do
    # The regression: 10 failed MetricsPollJobs (finished_at: nil but dead)
    # permanently wedged the scheduler. Failed jobs must be excluded so a
    # backlog of failures can't stop fresh polls from being enqueued.
    cap = 10
    (cap + 2).times do
      job = SolidQueue::Job.create!(
        queue_name: "metrics", class_name: "MetricsPollJob",
        arguments: { arguments: [ server.id ] }.to_json, finished_at: nil
      )
      SolidQueue::FailedExecution.create!(job: job, error: { exception_class: "Errno::ECONNRESET" }.to_json)
    end

    expect { described_class.perform_now }
      .to have_enqueued_job(MetricsPollJob).with(server.id)
  end
end

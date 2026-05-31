# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReconcileAppStatusesSchedulerJob, type: :job do
  let!(:s) { create(:server) }

  it "enqueues ReconcileAppStatusesJob per server" do
    expect {
      described_class.new.perform
    }.to have_enqueued_job(ReconcileAppStatusesJob).exactly(Server.count).times.on_queue("health")
  end

  it "skips when too many ReconcileAppStatusesJobs are already pending" do
    cap = [ Server.count * 2, 5 ].max
    (cap + 1).times do
      SolidQueue::Job.create!(class_name: "ReconcileAppStatusesJob", queue_name: "health",
                              arguments: { arguments: [ SecureRandom.uuid ] }.to_json)
    end
    expect {
      described_class.new.perform
    }.not_to have_enqueued_job(ReconcileAppStatusesJob)
  end
end

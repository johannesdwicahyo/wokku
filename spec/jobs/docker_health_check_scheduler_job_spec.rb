# frozen_string_literal: true

require "rails_helper"

RSpec.describe DockerHealthCheckSchedulerJob, type: :job do
  let!(:server) { create(:server) }

  it "enqueues one DockerHealthCheckJob per server" do
    expect {
      described_class.new.perform
    }.to have_enqueued_job(DockerHealthCheckJob).exactly(Server.count).times.on_queue("health")
  end

  it "skips the tick when pending DockerHealthCheckJob count exceeds the cap" do
    cap = [ Server.count * 2, 5 ].max
    (cap + 1).times do
      SolidQueue::Job.create!(class_name: "DockerHealthCheckJob", queue_name: "health",
                              arguments: { arguments: [ SecureRandom.uuid ] }.to_json)
    end
    expect {
      described_class.new.perform
    }.not_to have_enqueued_job(DockerHealthCheckJob)
  end
end

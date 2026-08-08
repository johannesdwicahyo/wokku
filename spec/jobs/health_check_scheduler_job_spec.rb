# frozen_string_literal: true

require "rails_helper"

RSpec.describe HealthCheckSchedulerJob, type: :job do
  let(:user) { create(:user) }
  let(:team) { create(:team, owner: user) }
  let!(:server) { create(:server, team: team) }

  describe "skip-if-pending guard" do
    it "enqueues one HealthCheckJob per server on the happy path" do
      expect {
        described_class.new.perform
      }.to have_enqueued_job(HealthCheckJob).exactly(Server.count).times.on_queue("health")
    end

    it "skips the tick when pending HealthCheckJob count exceeds the cap" do
      cap = [ Server.count * 2, 10 ].max
      (cap + 1).times do
        SolidQueue::Job.create!(class_name: "HealthCheckJob", queue_name: "health",
                                arguments: { arguments: [ SecureRandom.uuid ] }.to_json)
      end

      expect {
        described_class.new.perform
      }.not_to have_enqueued_job(HealthCheckJob)
    end

    it "does NOT count failed executions toward the cap" do
      # Regression: HealthCheckJob wedged in prod on 2026-06-16 — exactly 10
      # failed executions (finished_at: nil but dead) tripped the cap and the
      # scheduler skipped every tick. Failed jobs must be excluded.
      cap = [ Server.count * 2, 10 ].max
      (cap + 2).times do
        job = SolidQueue::Job.create!(class_name: "HealthCheckJob", queue_name: "health",
                                      arguments: { arguments: [ SecureRandom.uuid ] }.to_json)
        SolidQueue::FailedExecution.create!(job: job, error: { exception_class: "Errno::ECONNRESET" }.to_json)
      end

      expect {
        described_class.new.perform
      }.to have_enqueued_job(HealthCheckJob).exactly(Server.count).times
    end
  end
end

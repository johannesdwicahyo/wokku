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
  end
end

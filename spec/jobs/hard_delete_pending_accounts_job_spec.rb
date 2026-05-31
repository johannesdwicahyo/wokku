# frozen_string_literal: true

require "rails_helper"

RSpec.describe HardDeletePendingAccountsJob, type: :job do
  let!(:past_due) { User.create!(email: "past-#{SecureRandom.hex(4)}@example.com", password: "password123456", deletion_scheduled_at: 1.second.ago) }
  let!(:future) { User.create!(email: "future-#{SecureRandom.hex(4)}@example.com", password: "password123456", deletion_scheduled_at: 1.day.from_now) }
  let!(:not_sched) { User.create!(email: "clean-#{SecureRandom.hex(4)}@example.com", password: "password123456") }
  let!(:hard_deleted) { User.create!(email: "gone-#{SecureRandom.hex(4)}@example.com", password: "password123456", deletion_scheduled_at: 2.days.ago, deleted_at: 1.day.ago) }

  before do
    [ past_due, future, not_sched, hard_deleted ].each_with_index do |u, i|
      Team.create!(name: "Team-#{SecureRandom.hex(3)}-#{i}", owner: u)
    end
  end

  it "enqueues HardDeleteAccountJob only for past-due users" do
    expect { described_class.perform_now }.to have_enqueued_job(HardDeleteAccountJob).with(past_due.id)

    # Verify negative cases by inspecting enqueued_jobs
    enqueued_ids = ActiveJob::Base.queue_adapter.enqueued_jobs
                     .select { |j| j[:job] == HardDeleteAccountJob }
                     .map { |j| j[:args].first }
    expect(enqueued_ids).not_to include(future.id)
    expect(enqueued_ids).not_to include(not_sched.id)
    expect(enqueued_ids).not_to include(hard_deleted.id)
  end
end

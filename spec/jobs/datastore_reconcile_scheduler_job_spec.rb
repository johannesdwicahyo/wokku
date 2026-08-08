# frozen_string_literal: true

require "rails_helper"

RSpec.describe DatastoreReconcileSchedulerJob, type: :job do
  it "enqueues the reconcile worker" do
    expect { described_class.perform_now }.to have_enqueued_job(DatastoreReconcileJob).on_queue("health")
  end
end

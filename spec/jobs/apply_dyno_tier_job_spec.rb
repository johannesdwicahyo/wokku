# frozen_string_literal: true

require "rails_helper"

# Legacy shim: jobs enqueued before the per-resource deploy carry a
# DynoAllocation id, not an app id. Delete in P4 cleanup.
RSpec.describe ApplyDynoTierJob, type: :job do
  let(:app) { create(:app_record) }
  let!(:allocation) { app.dyno_allocations.create!(process_type: "web", count: 1, cpu: 0.5, memory_mb: 512) }

  it "delegates to ApplyResourcesJob with the allocation's app id" do
    expect(ApplyResourcesJob).to receive(:perform_now).with(app.id)
    described_class.perform_now(allocation.id)
  end

  it "no-ops when the allocation is gone" do
    expect(ApplyResourcesJob).not_to receive(:perform_now)
    described_class.perform_now(-1)
  end
end

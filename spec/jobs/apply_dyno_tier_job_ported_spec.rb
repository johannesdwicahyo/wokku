# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplyDynoTierJob, type: :job do
  let(:app) { app_records(:one) }
  let(:tier) { dyno_tiers(:basic) }
  let!(:allocation) { app.dyno_allocations.create!(process_type: "web", dyno_tier: tier, count: 2) }

  it "returns early when allocation not found" do
    expect(Lifecycle::Ops).not_to receive(:converge!)
    described_class.perform_now(-1)
  end

  # PR #49: resizes no longer force a restart — wokkud rolls only the
  # processes whose spec (incl. resources) changed.
  it "converges without a forced restart and clears the resize banner" do
    app.update!(pending_action: "resize")
    expect(Lifecycle::Ops).to receive(:converge!).with(have_attributes(id: app.id))

    described_class.perform_now(allocation.id)
    expect(app.reload.pending_action).to be_nil
  end

  it "handles Lifecycle::Ops::Failed — clears pending_action, no raise" do
    app.update!(pending_action: "resize")
    op = build_stubbed(:lifecycle_op, status: :failed, error: "no route", error_code: "connect_failed")
    allow(Lifecycle::Ops).to receive(:converge!).and_raise(Lifecycle::Ops::Failed.new(op))

    expect { described_class.perform_now(allocation.id) }.not_to raise_error
    expect(app.reload.pending_action).to be_nil
  end

  # M1: Busy is a SIBLING of Failed/Timeout, not a subclass — a resize racing
  # the post-deploy prune window (or any other in-flight op) must be handled
  # exactly like Failed, not wedge the scaling page's "Resizing…" banner forever.
  it "handles Lifecycle::Ops::Busy the same as Failed — clears pending_action, no raise" do
    app.update!(pending_action: "resize")
    allow(Lifecycle::Ops).to receive(:converge!).and_raise(Lifecycle::Ops::Busy.new(app))

    expect { described_class.perform_now(allocation.id) }.not_to raise_error
    expect(app.reload.pending_action).to be_nil
  end
end

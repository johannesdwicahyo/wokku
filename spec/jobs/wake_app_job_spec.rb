# frozen_string_literal: true

require "rails_helper"

RSpec.describe WakeAppJob, type: :job do
  let(:app) { app_records(:one) }

  before { app.update!(status: :sleeping) }

  it "wakes a sleeping app and transitions to running" do
    expect(Lifecycle::Ops).to receive(:converge!).with(have_attributes(id: app.id))
    described_class.perform_now(app.id)
    expect(app.reload).to be_running
  end

  it "does nothing when app is not sleeping" do
    app.update!(status: :running)
    expect(Lifecycle::Ops).not_to receive(:converge!)
    described_class.perform_now(app.id)
  end

  it "does nothing when app id not found" do
    expect(Lifecycle::Ops).not_to receive(:converge!)
    described_class.perform_now("00000000-0000-7000-8000-000000000000")
  end

  it "logs but does not raise when the converge fails" do
    op = build_stubbed(:lifecycle_op, status: :failed, error: "no route", error_code: "connect_failed")
    allow(Lifecycle::Ops).to receive(:converge!).and_raise(Lifecycle::Ops::Failed.new(op))
    expect { described_class.perform_now(app.id) }.not_to raise_error
    expect(app.reload).to be_sleeping
  end

  # M2: Busy is a SIBLING of Failed/Timeout, not a subclass — an unrescued
  # Busy otherwise means a wake click silently dies (job raises, app stays
  # "sleeping" with no error surfaced).
  it "logs but does not raise when Lifecycle::Ops::Busy is raised" do
    allow(Lifecycle::Ops).to receive(:converge!).and_raise(Lifecycle::Ops::Busy.new(app))

    expect { described_class.perform_now(app.id) }.not_to raise_error
    expect(app.reload).to be_sleeping
  end
end

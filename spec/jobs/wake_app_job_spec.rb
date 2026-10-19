# frozen_string_literal: true

require "rails_helper"

RSpec.describe WakeAppJob, type: :job do
  let(:app) { app_records(:one) }

  before do
    app.dyno_allocations.create!(process_type: "web", count: 1, dyno_tier: create(:dyno_tier, sleeps: true))
    app.update!(status: :sleeping)
  end

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

  it "stamps last_request_at so the woken app gets a full idle window" do
    allow(Lifecycle::Ops).to receive(:converge!)
    freeze_time do
      described_class.perform_now(app.id)
      expect(app.reload.last_request_at).to eq(Time.current)
    end
  end

  # A billing-suspended paid app also sits at status: sleeping — a visit
  # must never bring it back up.
  it "does not wake a sleeping app on a paid tier" do
    app.dyno_allocations.first.update!(dyno_tier: create(:dyno_tier, sleeps: false))
    expect(Lifecycle::Ops).not_to receive(:converge!)
    described_class.perform_now(app.id)
    expect(app.reload).to be_sleeping
  end

  it "logs and leaves the app sleeping when it has no image source" do
    allow(Lifecycle::Ops).to receive(:converge!).and_raise(ArgumentError, "no image source")
    expect { described_class.perform_now(app.id) }.not_to raise_error
    expect(app.reload).to be_sleeping
  end

  it "logs and leaves the app sleeping when its team may not run apps" do
    allow(Lifecycle::Ops).to receive(:converge!).and_raise(Lifecycle::Ops::RunNotAllowed.new(app))
    expect { described_class.perform_now(app.id) }.not_to raise_error
    expect(app.reload).to be_sleeping
  end
end

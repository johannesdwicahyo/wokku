# frozen_string_literal: true

require "rails_helper"

RSpec.describe IdleCheckJob, type: :job do
  let(:app) { app_records(:one) }
  let!(:eco) do
    DynoTier.find_or_create_by!(name: "eco") do |t|
      t.memory_mb = 256
      t.cpu_shares = 0.2
      t.price_cents_per_hour = 0.0685
      t.price_cents_per_month = 250
    end
  end

  before do
    app.update!(status: :running)
    DynoAllocation.create!(app_record: app, dyno_tier: eco, process_type: "web", count: 1)
  end

  it "returns early when no eco tier exists" do
    DynoAllocation.where(dyno_tier: eco).destroy_all
    eco.destroy
    expect(Lifecycle::Ops).not_to receive(:converge!)
    described_class.perform_now
  end

  it "puts an idle eco app to sleep with an all-zero formation (allow_empty)" do
    app.process_scales.delete_all
    app.process_scales.create!(process_type: "web", count: 1)
    expect(Lifecycle::Ops).to receive(:converge!)
      .with(have_attributes(id: app.id), formation: { "web" => 0 }, allow_empty: true)
    described_class.perform_now
    expect(app.reload.sleeping?).to be_truthy
  end

  it "skips app that received a request within the threshold" do
    app.metrics.create!(recorded_at: 1.minute.ago, memory_usage: 50, cpu_percent: 1.0)
    expect(Lifecycle::Ops).not_to receive(:converge!)
    described_class.perform_now
    expect(app.reload.sleeping?).to be_falsey
  end

  it "swallows Lifecycle::Ops::Failed" do
    op = build_stubbed(:lifecycle_op, status: :failed, error: "x", error_code: "y")
    allow(Lifecycle::Ops).to receive(:converge!).and_raise(Lifecycle::Ops::Failed.new(op))
    expect { described_class.perform_now }.not_to raise_error
  end

  # M3: Busy is a SIBLING of Failed/Timeout, not a subclass — an escaped
  # Busy otherwise aborts the whole eco-idle sweep mid-find_each, leaving
  # every subsequent eco app unchecked.
  it "swallows Lifecycle::Ops::Busy and keeps sweeping other apps" do
    other = app_records(:two)
    other.update!(status: :running)
    DynoAllocation.create!(app_record: other, dyno_tier: eco, process_type: "web", count: 1)

    call_count = 0
    allow(Lifecycle::Ops).to receive(:converge!) do
      call_count += 1
      raise Lifecycle::Ops::Busy.new(app) if call_count == 1
    end

    expect { described_class.perform_now }.not_to raise_error
    expect(call_count).to eq(2)
  end

  # Finding 1b (review wave 2): a post-adopt app with no image source raises
  # ArgumentError from converge! — one bad app must not abort the sweep.
  it "swallows ArgumentError (post-adopt app with no image source) and still processes other apps" do
    other = app_records(:two)
    other.update!(status: :running)
    DynoAllocation.create!(app_record: other, dyno_tier: eco, process_type: "web", count: 1)

    call_count = 0
    allow(Lifecycle::Ops).to receive(:converge!) do
      call_count += 1
      raise ArgumentError, "no image for x" if call_count == 1
    end

    expect { described_class.perform_now }.not_to raise_error
    expect(call_count).to eq(2)
  end
end

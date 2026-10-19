require "rails_helper"

RSpec.describe IdleCheckJob, type: :job do
  let(:free_tier) { create(:dyno_tier, name: "free-test", sleeps: true) }
  let(:paid_tier) { create(:dyno_tier, name: "basic-test", sleeps: false) }

  def app_on(tier, last_request_at:, **attrs)
    create(:app_record, status: :running, last_request_at: last_request_at, **attrs).tap do |a|
      a.dyno_allocations.create!(process_type: "web", count: 1, dyno_tier: tier)
    end
  end

  before { allow(Lifecycle::Ops).to receive(:converge!) }

  it "sleeps a free app idle for over 30 minutes" do
    app = app_on(free_tier, last_request_at: 31.minutes.ago)
    described_class.perform_now
    expect(Lifecycle::Ops).to have_received(:converge!).with(app, formation: { "web" => 0 }, allow_empty: true)
    expect(app.reload).to be_sleeping
  end

  it "keeps recently visited, never-observed, and paid apps running" do
    recent = app_on(free_tier, last_request_at: 10.minutes.ago)
    unknown = app_on(free_tier, last_request_at: nil)
    paid = app_on(paid_tier, last_request_at: 2.hours.ago)
    described_class.perform_now
    expect([ recent, unknown, paid ].map { |a| a.reload.status }).to all(eq("running"))
  end

  it "keeps an app deployed in the last 30 minutes running" do
    app = app_on(free_tier, last_request_at: 2.hours.ago)
    create(:deploy, app_record: app, status: :succeeded, finished_at: 5.minutes.ago)
    described_class.perform_now
    expect(app.reload).to be_running
  end

  it "never sleeps a free app with no domain (no visit data)" do
    app = app_on(free_tier, last_request_at: nil)
    expect(app.domains).to be_empty
    described_class.perform_now
    expect(app.reload).to be_running
  end

  it "continues the sweep past a failing app" do
    bad = app_on(free_tier, last_request_at: 2.hours.ago)
    good = app_on(free_tier, last_request_at: 2.hours.ago)
    allow(Lifecycle::Ops).to receive(:converge!).with(bad, anything).and_raise(ArgumentError, "no image")
    described_class.perform_now
    expect(bad.reload).to be_running
    expect(good.reload).to be_sleeping
  end

  it "never sleeps a shaped (paid) allocation even on a sleeping tier" do
    app = create(:app_record, status: :running, last_request_at: 2.hours.ago)
    app.dyno_allocations.create!(process_type: "web", count: 1, dyno_tier: free_tier, cpu: 0.5, memory_mb: 512)
    described_class.perform_now
    expect(Lifecycle::Ops).not_to have_received(:converge!)
    expect(app.reload).to be_running
  end

  # A suspended owner's slept free app could never wake (converge raises
  # RunNotAllowed) — leave it up, as before wake-on-request.
  it "never sleeps an app whose team may not run apps" do
    app = app_on(free_tier, last_request_at: 2.hours.ago)
    allow_any_instance_of(AppRecord).to receive(:run_allowed?).and_return(false)
    described_class.perform_now
    expect(Lifecycle::Ops).not_to have_received(:converge!)
    expect(app.reload).to be_running
  end

  # A visit (or a user stop) landing during a long serial sweep must win.
  it "re-checks idleness right before sleeping each app" do
    first = app_on(free_tier, last_request_at: 3.hours.ago)
    second = app_on(free_tier, last_request_at: 2.hours.ago)
    allow(Lifecycle::Ops).to receive(:converge!) do |a, **|
      other = a.id == first.id ? second : first
      other.update_column(:last_request_at, Time.current)
    end
    described_class.perform_now
    expect(Lifecycle::Ops).to have_received(:converge!).once
    expect([ first, second ].map { |a| a.reload.status }.sort).to eq(%w[running sleeping])
  end

  it "logs any per-app error and continues the sweep" do
    bad = app_on(free_tier, last_request_at: 2.hours.ago)
    good = app_on(free_tier, last_request_at: 2.hours.ago)
    allow(Lifecycle::Ops).to receive(:converge!).with(bad, anything).and_raise(RuntimeError, "boom")
    described_class.perform_now
    expect(bad.reload).to be_running
    expect(good.reload).to be_sleeping
  end
end

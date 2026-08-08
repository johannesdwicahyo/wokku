require "rails_helper"

RSpec.describe CrashLoopDetectorJob do
  let(:server) { create(:server, status: :connected, ssh_private_key: "dummy-key") }
  let(:app)    { create(:app_record, server: server, name: "loopy", status: :running) }

  def docker_output(rows)
    allow_any_instance_of(described_class).to receive(:fetch_container_rows).and_return(rows)
  end

  before do
    app
    # test env uses :null_store; give the job a real cache so the debounce persists
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    allow(Sentry).to receive(:capture_message)
  end

  it "marks the app :crashed and fires app_crashed when >=3 web containers crashed in 5 min" do
    rows = 3.times.map { |i| { app: "loopy", crashed: true, age_seconds: 60 * (i + 1) } }
    docker_output(rows)
    expect_any_instance_of(described_class).to receive(:fire_resource_alert).with(app.team, "app_crashed", app)
    expect(Sentry).to receive(:capture_message).with(/crash-loop/, hash_including(level: :warning))
    described_class.perform_now(server.id)
    expect(app.reload.status).to eq("crashed")
  end

  it "does not alert for a healthy app (no recent crashes)" do
    docker_output([ { app: "loopy", crashed: false, age_seconds: 30 } ])
    expect_any_instance_of(described_class).not_to receive(:fire_resource_alert)
    described_class.perform_now(server.id)
    expect(app.reload.status).to eq("running")
  end

  it "alerts only once per episode (debounced), then resets when healthy" do
    rows = 3.times.map { |i| { app: "loopy", crashed: true, age_seconds: 60 * (i + 1) } }
    docker_output(rows)
    expect_any_instance_of(described_class).to receive(:fire_resource_alert).once
    described_class.perform_now(server.id)
    described_class.perform_now(server.id)
    docker_output([ { app: "loopy", crashed: false, age_seconds: 10 } ])
    described_class.perform_now(server.id)
  end

  describe "crash capture" do
    it "records a CrashEvent (exit code, oom, log excerpt) for a newly-crashed container" do
      rows = [ { app: "loopy", crashed: true, age_seconds: 60, name: "loopy.web.1.aaa" } ]
      allow_any_instance_of(described_class).to receive(:fetch_container_rows).and_return(rows)
      allow_any_instance_of(described_class).to receive(:fetch_crash_details)
        .and_return({ exit_code: 137, oom_killed: true, logs: "too many connections" })

      expect { described_class.perform_now(server.id) }.to change { app.reload.crash_events.count }.by(1)
      ev = app.crash_events.last
      expect(ev.exit_code).to eq(137)
      expect(ev.oom_killed).to be(true)
      expect(ev.log_excerpt).to include("too many connections")
      expect(ev.container_id).to eq("loopy.web.1.aaa")
    end

    it "does not double-record the same container" do
      app.crash_events.create!(container_id: "loopy.web.1.aaa", exit_code: 1, exited_at: Time.current)
      rows = [ { app: "loopy", crashed: true, age_seconds: 60, name: "loopy.web.1.aaa" } ]
      allow_any_instance_of(described_class).to receive(:fetch_container_rows).and_return(rows)
      expect_any_instance_of(described_class).not_to receive(:fetch_crash_details)
      expect { described_class.perform_now(server.id) }.not_to change { CrashEvent.count }
    end
  end

  describe "tier 2 (auto-stop)" do
    around do |ex|
      orig = ENV["CRASH_LOOP_AUTO_STOP"]
      ENV["CRASH_LOOP_AUTO_STOP"] = "true"
      ex.run
    ensure
      ENV["CRASH_LOOP_AUTO_STOP"] = orig
    end

    before do
      @alerts = []
      allow_any_instance_of(described_class).to receive(:fire_resource_alert) { |_, _team, event, _app| @alerts << event }
      allow(Lifecycle::Ops).to receive(:converge!)
    end

    it "converges a zeroed formation and escalates when >=10 crashes in 15 min" do
      rows = 10.times.map { |i| { app: "loopy", crashed: true, age_seconds: 60 * (i + 1) } }
      allow_any_instance_of(described_class).to receive(:fetch_container_rows).and_return(rows)
      expect(Lifecycle::Ops).to receive(:converge!)
        .with(app, formation: Lifecycle::Ops.stop_formation(app), allow_empty: true)
      described_class.perform_now(server.id)
      expect(@alerts).to include("app_auto_stopped")
    end

    it "does NOT auto-stop when the flag is off" do
      ENV["CRASH_LOOP_AUTO_STOP"] = "false"
      rows = 10.times.map { |i| { app: "loopy", crashed: true, age_seconds: 60 * (i + 1) } }
      allow_any_instance_of(described_class).to receive(:fetch_container_rows).and_return(rows)
      expect(Lifecycle::Ops).not_to receive(:converge!)
      described_class.perform_now(server.id)
    end
  end
end

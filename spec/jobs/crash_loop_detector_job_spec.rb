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

    it "does not record a container Wokku stopped on purpose (app asleep)" do
      app.update!(status: :sleeping)
      rows = [ { app: "loopy", crashed: true, age_seconds: 60, name: "loopy.web.1.zzz" } ]
      allow_any_instance_of(described_class).to receive(:fetch_container_rows).and_return(rows)
      expect_any_instance_of(described_class).not_to receive(:fetch_crash_details)
      expect { described_class.perform_now(server.id) }.not_to change { CrashEvent.count }
    end

    it "does not double-record the same container" do
      app.crash_events.create!(container_id: "loopy.web.1.aaa", exit_code: 1, exited_at: Time.current)
      rows = [ { app: "loopy", crashed: true, age_seconds: 60, name: "loopy.web.1.aaa" } ]
      allow_any_instance_of(described_class).to receive(:fetch_container_rows).and_return(rows)
      expect_any_instance_of(described_class).not_to receive(:fetch_crash_details)
      expect { described_class.perform_now(server.id) }.not_to change { CrashEvent.count }
    end

    it "shrugs off a RecordNotUnique race with another poll" do
      app.crash_events.create!(container_id: "loopy.web.1.aaa", exit_code: 1, exited_at: Time.current)
      # simulate the race: the dedupe check misses the row the other poll just wrote
      allow(CrashEvent).to receive(:where).and_return(instance_double(ActiveRecord::Relation, exists?: false))
      rows = [ { app: "loopy", crashed: true, age_seconds: 60, name: "loopy.web.1.aaa" } ]
      docker_output(rows)
      allow_any_instance_of(described_class).to receive(:fetch_crash_details)
        .and_return({ exit_code: 1, oom_killed: false, logs: "boom" })
      expect { described_class.perform_now(server.id) }.not_to change { CrashEvent.count }
    end
  end

  it "logs and reports to Sentry when the poll blows up" do
    allow_any_instance_of(described_class).to receive(:fetch_container_rows).and_raise(RuntimeError, "boom")
    allow(Rails.logger).to receive(:warn)
    expect(Sentry).to receive(:capture_exception).with(instance_of(RuntimeError), hash_including(level: :warning))
    expect { described_class.perform_now(server.id) }.not_to raise_error
    expect(Rails.logger).to have_received(:warn).with(/CrashLoopDetectorJob: .*boom/)
  end

  describe "#fetch_crash_details" do
    let(:job) { described_class.new }

    it "reads exit code, OOM flag, and logs over SSH" do
      ssh = double("ssh")
      allow(ssh).to receive(:exec!).with(/docker inspect/).and_return("137|true\n")
      allow(ssh).to receive(:exec!).with(/docker logs/).and_return("out of memory")
      allow(Net::SSH).to receive(:start).and_yield(ssh)
      details = job.send(:fetch_crash_details, server, "loopy.web.1.aaa")
      expect(details).to eq(exit_code: 137, oom_killed: true, logs: "out of memory")
    end

    it "returns nil when the host is unreachable" do
      allow(Net::SSH).to receive(:start).and_raise(Errno::ECONNREFUSED)
      expect(job.send(:fetch_crash_details, server, "loopy.web.1.aaa")).to be_nil
    end
  end

  describe "#fetch_container_rows" do
    let(:job) { described_class.new }
    let(:two_min_ago) { (Time.now - 120).strftime("%Y-%m-%d %H:%M:%S %z") }

    def stub_docker_ps(raw)
      allow(Net::SSH).to receive(:start).and_return(raw)
    end

    it "parses exited app containers (Dokku and Swarm names, every process) and skips infra, one-off runs, and junk" do
      create(:app_record, server: server, name: "loopy-api")
      raw = <<~OUT
        loopy.web.1.aaa|Exited (1) 2 minutes ago|#{two_min_ago}
        loopy.web.1.bbb|Exited (0) 2 minutes ago|#{two_min_ago}
        loopy.web.1.ccc|Up 2 minutes|#{two_min_ago}
        loopy.web.1.ddd|Exited (1) 2 minutes ago|not-a-timestamp
        loopy.worker.1.eee|Exited (1) 2 minutes ago|#{two_min_ago}
        wokku-loopy-worker.1.s1|Exited (1) 2 minutes ago|#{two_min_ago}
        wokku-loopy-web.1.s2|Exited (143) 2 minutes ago|#{two_min_ago}
        wokku-loopy-api-web.1.s3|Exited (137) 2 minutes ago|#{two_min_ago}
        wokku-run-loopy-0a1b2c3d.1.s4|Exited (1) 2 minutes ago|#{two_min_ago}
        dokku.web.1.fff|Exited (1) 2 minutes ago|#{two_min_ago}
        garbage-line
      OUT
      stub_docker_ps(raw)
      rows = job.send(:fetch_container_rows, server).index_by { |r| r[:name] }
      expect(rows.keys).to contain_exactly("loopy.web.1.aaa", "loopy.web.1.bbb", "loopy.worker.1.eee",
                                           "wokku-loopy-worker.1.s1", "wokku-loopy-web.1.s2", "wokku-loopy-api-web.1.s3")
      expect(rows["loopy.web.1.aaa"]).to include(app: "loopy", crashed: true)
      expect(rows["loopy.web.1.aaa"][:age_seconds]).to be_within(5).of(120)
      expect(rows["loopy.web.1.bbb"][:crashed]).to be(false)
      expect(rows["wokku-loopy-worker.1.s1"]).to include(app: "loopy", crashed: true)
      expect(rows["wokku-loopy-web.1.s2"][:crashed]).to be(false) # SIGTERM from a rollout
      expect(rows["wokku-loopy-api-web.1.s3"]).to include(app: "loopy-api", crashed: true)
    end

    it "returns nil when docker is down on the host" do
      stub_docker_ps("Cannot connect to the Docker daemon at unix:///var/run/docker.sock")
      expect(job.send(:fetch_container_rows, server)).to be_nil
    end

    it "returns nil when SSH fails" do
      allow(Net::SSH).to receive(:start).and_raise(SocketError)
      expect(job.send(:fetch_container_rows, server)).to be_nil
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

  it "SSHes as the configured host SSH user for container rows and crash details" do
    allow(Wokku.config).to receive(:host_ssh_user).and_return("wokku")
    fake_ssh = double("ssh", exec!: "")
    allow(Net::SSH).to receive(:start).and_yield(fake_ssh)
    job = described_class.new
    job.send(:fetch_container_rows, server)
    job.send(:fetch_crash_details, server, "loopy.web.1")
    expect(Net::SSH).to have_received(:start).with(server.host, "wokku", anything).twice
  end
end

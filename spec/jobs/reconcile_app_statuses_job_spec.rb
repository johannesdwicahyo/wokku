# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReconcileAppStatusesJob, type: :job do
  let(:user) { create(:user) }
  let(:team) do
    t = create(:team, owner: user)
    create(:team_membership, team: t, user: user, role: :admin)
    t
  end
  let(:server) { create(:server, team: team, ssh_private_key: "fake-key-#{SecureRandom.hex(4)}") }

  def make_app(name:, status: :running)
    create(:app_record, team: team, server: server, creator: user, name: name, status: status)
  end

  def stub_docker_ps(output)
    fake_ssh = double("ssh")
    allow(fake_ssh).to receive(:exec!).and_return(output)
    allow(Net::SSH).to receive(:start).and_yield(fake_ssh)
  end

  describe "flagged apps — status from live_containers (B6 W4)" do
    def make_flagged(name:, status:, tasks:, at: Time.current)
      app = make_app(name: name, status: status)
      app.update_columns(wokkud_lifecycle: true, live_containers: tasks, live_containers_at: at)
      app
    end

    before { stub_docker_ps("") }

    it "flips running -> crashed when no web task is running" do
      app = make_flagged(name: "swarmed", status: :running,
        tasks: [ { "process" => "web", "state" => "failed" } ])
      allow(Sentry).to receive(:capture_message)

      described_class.perform_now(server.id)

      expect(app.reload.status).to eq("crashed")
    end

    it "flips crashed -> running when the web task recovers" do
      app = make_flagged(name: "swarmed", status: :crashed,
        tasks: [ { "process" => "web", "state" => "running" } ])
      allow(Sentry).to receive(:capture_message)

      described_class.perform_now(server.id)

      expect(app.reload.status).to eq("running")
    end

    it "never guesses on a stale heartbeat" do
      app = make_flagged(name: "swarmed", status: :running,
        tasks: [ { "process" => "web", "state" => "failed" } ], at: 30.minutes.ago)

      described_class.perform_now(server.id)

      expect(app.reload.status).to eq("running")
    end

    it "never auto-flips intentional stopped/sleeping states" do
      app = make_flagged(name: "swarmed", status: :sleeping, tasks: [])

      described_class.perform_now(server.id)

      expect(app.reload.status).to eq("sleeping")
    end
  end

  describe "no drift" do
    it "is silent when statuses match container state" do
      make_app(name: "alpha", status: :running)
      make_app(name: "beta",  status: :sleeping)
      stub_docker_ps("alpha.web.1\nalpha.web.1.upcoming-12345\n")

      expect(Sentry).not_to receive(:capture_message)
      described_class.new.perform(server.id)
    end
  end

  describe "drift: AppRecord :running but no container" do
    it "Sentry-warns with the discrepancy" do
      a = make_app(name: "ghost", status: :running)
      stub_docker_ps("other.web.1\n")

      expect(Sentry).to receive(:capture_message).with(
        /1 drift/,
        hash_including(extra: hash_including(discrepancies: include(/ghost/)))
      )
      described_class.new.perform(server.id)
      expect(a.reload.status).to eq("crashed") # v2 — writes drifted status
    end
  end

  describe "Swarm-lifecycle apps (C1)" do
    it "does NOT flip a flagged :running app to :crashed even with no dokku container" do
      a = make_app(name: "swarmed", status: :running)
      a.update!(wokkud_lifecycle: true)
      stub_docker_ps("other.web.1\n") # its swarm task container never matches split(".").first

      expect(Sentry).not_to receive(:capture_message)
      described_class.new.perform(server.id)
      expect(a.reload.status).to eq("running")
    end
  end

  describe "status writes (v2)" do
    it "sets :running when a container is live but the record says crashed" do
      a = make_app(name: "revived", status: :crashed)
      stub_docker_ps("revived.web.1\n")
      described_class.new.perform(server.id)
      expect(a.reload.status).to eq("running")
    end

    it "does NOT touch an intentionally-stopped app with no container" do
      a = make_app(name: "paused", status: :stopped)
      stub_docker_ps("other.web.1\n")
      described_class.new.perform(server.id)
      expect(a.reload.status).to eq("stopped")
    end
  end

  describe "drift: AppRecord :sleeping but container running" do
    it "Sentry-warns" do
      a = make_app(name: "zombie", status: :sleeping)
      stub_docker_ps("zombie.web.1\n")

      expect(Sentry).to receive(:capture_message).with(
        /1 drift/,
        hash_including(extra: hash_including(discrepancies: include(/zombie/)))
      )
      described_class.new.perform(server.id)
      expect(a.reload.status).to eq("sleeping") # read-only
    end
  end

  describe "drift warning debounce" do
    # Use a real cache so the per-signature debounce actually persists across
    # runs (the test default :null_store would make every run re-warn).
    before { allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new) }

    it "Sentry-warns only once for the same persistent drift across repeated runs" do
      # :sleeping + live container is the warn-only case (never self-resolves),
      # so it would otherwise fire on every 10-min poll.
      make_app(name: "zombie", status: :sleeping)
      stub_docker_ps("zombie.web.1\n")

      expect(Sentry).to receive(:capture_message).once
      3.times { described_class.new.perform(server.id) }
    end

    it "warns again when the set of drifting apps changes" do
      make_app(name: "zombie", status: :sleeping)
      make_app(name: "ghost2", status: :sleeping)
      stub_docker_ps("zombie.web.1\n")

      expect(Sentry).to receive(:capture_message).twice
      described_class.new.perform(server.id)            # drift: {zombie}
      stub_docker_ps("zombie.web.1\nghost2.web.1\n")    # drift: {zombie, ghost2} -> new signature
      described_class.new.perform(server.id)
    end
  end

  describe "docker daemon down" do
    it "skips quietly (separate alert path via DockerHealthCheckJob)" do
      make_app(name: "alpha", status: :running)
      stub_docker_ps("Cannot connect to the Docker daemon at unix:///var/run/docker.sock.\n")

      expect(Sentry).not_to receive(:capture_message)
      described_class.new.perform(server.id)
    end
  end

  describe "SSH unreachable" do
    it "skips quietly" do
      make_app(name: "alpha", status: :running)
      allow(Net::SSH).to receive(:start).and_raise(Errno::EHOSTUNREACH, "no route")

      expect(Sentry).not_to receive(:capture_message)
      described_class.new.perform(server.id)
    end
  end

  describe "ignored containers" do
    it "does not flag system containers (dokku-shared-postgres, prom01, etc.)" do
      make_app(name: "alpha", status: :running)
      stub_docker_ps([
        "alpha.web.1",
        "dokku-shared-postgres",
        "prom01.web.1",
        "dokku.postgres.batumas-postgres" # raw dokku service container
      ].join("\n") + "\n")

      expect(Sentry).not_to receive(:capture_message)
      described_class.new.perform(server.id)
    end
  end
end

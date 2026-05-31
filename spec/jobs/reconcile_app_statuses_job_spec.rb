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
      expect(a.reload.status).to eq("running") # read-only — no mutation
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

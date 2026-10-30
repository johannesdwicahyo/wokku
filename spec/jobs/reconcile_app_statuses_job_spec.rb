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

  describe "flagged apps — status from live_containers (B6 W4)" do
    def make_flagged(name:, status:, tasks:, at: Time.current)
      app = make_app(name: name, status: status)
      app.update_columns(wokkud_lifecycle: true, live_containers: tasks, live_containers_at: at)
      app
    end

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

    it "treats a worker-only app (web: 0) as alive on any running task" do
      app = make_flagged(name: "bot", status: :running,
        tasks: [ { "process" => "worker", "state" => "running" } ])
      app.process_scales.create!(process_type: "web", count: 0)
      app.process_scales.create!(process_type: "worker", count: 1)

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

  describe "drift warning debounce" do
    before { allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new) }

    it "Sentry-warns once per drift signature, again when it changes" do
      expect(Sentry).to receive(:capture_message).twice
      3.times { described_class.new.send(:report_drift, server, [ "a drifted" ]) }
      described_class.new.send(:report_drift, server, [ "a drifted", "b drifted" ])
    end
  end
end

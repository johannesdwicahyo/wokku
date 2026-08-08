# frozen_string_literal: true

require "rails_helper"

RSpec.describe DokkuAppActionJob, type: :job do
  let(:user) { User.create!(email: "action-job-#{SecureRandom.hex(4)}@example.com", password: "password123456") }
  let(:team) { Team.create!(name: "Action-#{SecureRandom.hex(4)}", owner: user) }
  let(:server) { Server.create!(name: "s-#{SecureRandom.hex(4)}", host: "1.2.3.4", team: team) }
  let(:app) { AppRecord.create!(name: "action-app-#{SecureRandom.hex(4)}", server: server, team: team, creator: user, status: :running) }

  it "raises ArgumentError on unknown action" do
    expect { described_class.new.perform(app.id, "lol") }.to raise_error(ArgumentError)
  end

  it "no-ops on unknown app" do
    expect(Lifecycle::Ops).not_to receive(:converge!)
    described_class.new.perform(SecureRandom.uuid, "restart")
  end

  it "restart converges with restart: true and leaves status running" do
    expect(Lifecycle::Ops).to receive(:converge!).with(have_attributes(id: app.id), restart: true)
    described_class.new.perform(app.id, "restart")
    expect(app.reload.status).to eq("running")
  end

  it "stop converges every process to zero (allow_empty) and flips to stopped" do
    app.process_scales.create!(process_type: "web", count: 1)
    app.process_scales.create!(process_type: "worker", count: 2)
    expect(Lifecycle::Ops).to receive(:converge!)
      .with(have_attributes(id: app.id), formation: { "web" => 0, "worker" => 0 }, allow_empty: true)
    described_class.new.perform(app.id, "stop")
    expect(app.reload.status).to eq("stopped")
  end

  it "start converges the formation and flips to running" do
    app.update!(status: :stopped)
    expect(Lifecycle::Ops).to receive(:converge!).with(have_attributes(id: app.id))
    described_class.new.perform(app.id, "start")
    expect(app.reload.status).to eq("running")
  end

  it "start failure via Lifecycle::Ops::Failed marks app crashed" do
    app.update!(status: :stopped)
    op = build_stubbed(:lifecycle_op, status: :failed, error: "no route", error_code: "connect_failed")
    allow(Lifecycle::Ops).to receive(:converge!).and_raise(Lifecycle::Ops::Failed.new(op))
    described_class.new.perform(app.id, "start")
    expect(app.reload.status).to eq("crashed")
  end

  it "restart failure does not flip status" do
    allow(Lifecycle::Ops).to receive(:converge!).and_raise(Lifecycle::Ops::Timeout, "op timed out")
    described_class.new.perform(app.id, "restart")
    expect(app.reload.status).to eq("running")
  end

  it "unexpected error clears pending_action so the UI doesn't get stuck" do
    app.update!(pending_action: "restart")
    allow(Lifecycle::Ops).to receive(:converge!).and_raise(Timeout::Error, "ssh stalled")
    described_class.new.perform(app.id, "restart")
    app.reload
    expect(app.pending_action).to be_nil
    expect(app.status).to eq("running")
  end
end

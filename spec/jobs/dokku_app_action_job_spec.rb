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
    expect_any_instance_of(Dokku::Processes).not_to receive(:restart)
    described_class.new.perform(SecureRandom.uuid, "restart")
  end

  it "restart calls Dokku::Processes#restart and leaves status running" do
    expect_any_instance_of(Dokku::Processes).to receive(:restart).with(app.name)
    described_class.new.perform(app.id, "restart")
    expect(app.reload.status).to eq("running")
  end

  it "stop flips status to stopped" do
    expect_any_instance_of(Dokku::Processes).to receive(:stop).with(app.name)
    described_class.new.perform(app.id, "stop")
    expect(app.reload.status).to eq("stopped")
  end

  it "start flips status to running" do
    app.update!(status: :stopped)
    expect_any_instance_of(Dokku::Processes).to receive(:start).with(app.name)
    described_class.new.perform(app.id, "start")
    expect(app.reload.status).to eq("running")
  end

  it "start failure marks app crashed" do
    app.update!(status: :stopped)
    allow_any_instance_of(Dokku::Processes).to receive(:start).and_raise(Dokku::Client::CommandError.new("boom"))
    described_class.new.perform(app.id, "start")
    expect(app.reload.status).to eq("crashed")
  end

  it "restart failure does not flip status" do
    allow_any_instance_of(Dokku::Processes).to receive(:restart).and_raise(Dokku::Client::ConnectionError, "ssh dead")
    described_class.new.perform(app.id, "restart")
    expect(app.reload.status).to eq("running")
  end

  it "unexpected error clears pending_action so the UI doesn't get stuck" do
    app.update!(pending_action: "restart")
    allow_any_instance_of(Dokku::Processes).to receive(:restart).and_raise(Timeout::Error, "ssh stalled")
    described_class.new.perform(app.id, "restart")
    app.reload
    expect(app.pending_action).to be_nil
    expect(app.status).to eq("running")
  end
end

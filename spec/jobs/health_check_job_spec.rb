# frozen_string_literal: true

require "rails_helper"

# W7 Phase 2: reachability truth is wokkud heartbeat freshness — no SSH.
RSpec.describe HealthCheckJob, type: :job do
  let(:server) { servers(:one) }

  it "sets server status to connected when the heartbeat is fresh" do
    server.update_column(:heartbeat_at, 5.seconds.ago)
    described_class.perform_now(server.id)
    expect(server.reload.status).to eq("connected")
  end

  it "sets server status to unreachable when the heartbeat is stale" do
    server.update_column(:heartbeat_at, 10.minutes.ago)
    described_class.perform_now(server.id)
    expect(server.reload.status).to eq("unreachable")
  end

  it "sets server status to unreachable when the host has never beat" do
    server.update_column(:heartbeat_at, nil)
    described_class.perform_now(server.id)
    expect(server.reload.status).to eq("unreachable")
  end

  describe "operator alerting on transition to unreachable" do
    before { server.update_column(:status, Server.statuses[:connected]) }

    it "reports to Sentry when a connected server transitions to unreachable" do
      server.update_column(:heartbeat_at, 10.minutes.ago)
      expect(Sentry).to receive(:capture_message).with(
        /unreachable/,
        hash_including(level: :error)
      )
      described_class.perform_now(server.id)
    end

    it "does NOT report to Sentry when the server was already unreachable" do
      server.update_column(:status, Server.statuses[:unreachable])
      server.update_column(:heartbeat_at, 10.minutes.ago)
      expect(Sentry).not_to receive(:capture_message)
      described_class.perform_now(server.id)
    end

    it "does NOT report to Sentry when the heartbeat is fresh" do
      server.update_column(:heartbeat_at, Time.current)
      expect(Sentry).not_to receive(:capture_message)
      described_class.perform_now(server.id)
    end
  end
end

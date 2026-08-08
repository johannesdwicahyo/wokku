# frozen_string_literal: true

require "rails_helper"

RSpec.describe Uptime::ReasonClassifier do
  let(:app) { create(:app_record, status: :running) }

  it "attributes host_down first, with 'not your code' copy" do
    app.server.update_columns(agent_version: "0.2.0", heartbeat_at: 5.minutes.ago)
    result = described_class.call(app, :timeout)
    expect(result.reason).to eq("host_down")
    expect(result.message).to include("not your code")
  end

  it "attributes app_stopped for a stopped app" do
    app.server.update_columns(agent_version: "0.2.0", heartbeat_at: Time.current)
    app.update_columns(status: AppRecord.statuses[:stopped])
    expect(described_class.call(app, :connection_refused).reason).to eq("app_stopped")
  end

  it "attributes app_crashed on crashed status" do
    app.server.update_columns(agent_version: "0.2.0", heartbeat_at: Time.current)
    app.update_columns(status: AppRecord.statuses[:crashed])
    expect(described_class.call(app, :connection_refused).reason).to eq("app_crashed")
  end

  it "attributes app_crashed on a recent CrashEvent even when status looks running" do
    app.server.update_columns(agent_version: "0.2.0", heartbeat_at: Time.current)
    create(:crash_event, app_record: app, exited_at: 1.minute.ago)
    expect(described_class.call(app, :http_5xx).reason).to eq("app_crashed")
  end

  it "falls through to the probe failure kind" do
    app.server.update_columns(agent_version: "0.2.0", heartbeat_at: Time.current)
    expect(described_class.call(app, :http_5xx).reason).to eq("http_5xx")
    expect(described_class.call(app, :timeout).reason).to eq("timeout")
  end

  it "does not blame the host when no agent is installed (heartbeat_stale? is vacuously true)" do
    app.server.update_columns(agent_version: nil, heartbeat_at: nil)
    expect(described_class.call(app, :http_5xx).reason).to eq("http_5xx")
  end
end

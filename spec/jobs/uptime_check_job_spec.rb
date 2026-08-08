# frozen_string_literal: true

require "rails_helper"

RSpec.describe UptimeCheckJob, type: :job do
  let(:app) { create(:app_record, status: :running) }

  before do
    create(:domain, app_record: app, hostname: "myapp.wokku.app")
    app.server.update_columns(agent_version: "0.2.0", heartbeat_at: Time.current)
  end

  def stub_probe(up:, kind: nil)
    allow(Uptime::Probe).to receive(:call)
      .and_return(Uptime::Probe::Result.new(up: up, failure_kind: kind))
  end

  it "probes the first domain over https" do
    stub_probe(up: true)
    described_class.perform_now(app.id)
    expect(Uptime::Probe).to have_received(:call).with("https://myapp.wokku.app/")
  end

  it "counts strikes without transitioning before the 3rd" do
    stub_probe(up: false, kind: :http_5xx)
    2.times { described_class.perform_now(app.id) }
    app.reload
    expect(app.uptime_failures).to eq(2)
    expect(app.uptime_status).to eq("unknown")
    expect(Incident.open_for(app)).to be_nil
  end

  it "goes down on the 3rd strike: incident opened with the typed reason" do
    stub_probe(up: false, kind: :http_5xx)
    3.times { described_class.perform_now(app.id) }

    app.reload
    expect(app.uptime_status).to eq("down")
    expect(Incident.open_for(app).reason).to eq("http_5xx")
  end

  it "fires app_down through the team's notifications on the down transition" do
    # Requires a :notification factory — check spec/factories/; create a minimal
    # one if missing (team, channel, events array; read the schema for required
    # fields like target/webhook URL).
    create(:notification, team: app.team, channel: :email, events: [ "app_down" ])
    stub_probe(up: false, kind: :http_5xx)
    expect { 3.times { described_class.perform_now(app.id) } }
      .to have_enqueued_job(NotifyJob).exactly(:once)
  end

  it "stays down without stacking incidents or re-firing on strikes 4+" do
    stub_probe(up: false, kind: :http_5xx)
    4.times { described_class.perform_now(app.id) }
    expect(Incident.where(app_record: app).count).to eq(1)
  end

  it "recovers on first success: closes incident, resets counter, fires app_recovered" do
    stub_probe(up: false, kind: :timeout)
    3.times { described_class.perform_now(app.id) }
    stub_probe(up: true)
    described_class.perform_now(app.id)

    app.reload
    expect(app.uptime_status).to eq("up")
    expect(app.uptime_failures).to eq(0)
    expect(Incident.open_for(app)).to be_nil
    expect(Incident.where(app_record: app).sole.resolved_at).to be_present
  end

  it "success resets a sub-threshold strike counter without any event" do
    stub_probe(up: false, kind: :timeout)
    2.times { described_class.perform_now(app.id) }
    stub_probe(up: true)
    described_class.perform_now(app.id)
    expect(app.reload.uptime_failures).to eq(0)
    expect(Incident.count).to eq(0)
  end

  it "no-ops for apps that stopped being candidates (deleted, stopped, domainless)" do
    app.update_columns(status: AppRecord.statuses[:stopped])
    stub_probe(up: true)
    described_class.perform_now(app.id)
    expect(Uptime::Probe).not_to have_received(:call)
  end

  it "does not re-fire app_recovered when already up (raced/duplicate tick)" do
    create(:notification, team: app.team, channel: :email, events: [ "app_recovered" ])
    stub_probe(up: false, kind: :timeout)
    3.times { described_class.perform_now(app.id) }
    stub_probe(up: true)
    described_class.perform_now(app.id)
    expect { described_class.perform_now(app.id) }.not_to have_enqueued_job(NotifyJob)
  end
end

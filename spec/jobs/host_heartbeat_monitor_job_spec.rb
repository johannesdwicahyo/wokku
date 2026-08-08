require "rails_helper"

RSpec.describe HostHeartbeatMonitorJob do
  it "marks a silent agent host down and pages once" do
    server = create(:server)
    server.update_columns(agent_version: "0.1.0", heartbeat_at: 2.minutes.ago, heartbeat_status: "ok")

    expect { described_class.perform_now }.to have_enqueued_mail(OpsMailer, :host_down)
    expect(server.reload.heartbeat_status).to eq("down")

    # Second run while still down: no second page.
    expect { described_class.perform_now }.not_to have_enqueued_mail(OpsMailer, :host_down)
  end

  it "leaves fresh hosts alone" do
    server = create(:server)
    server.update_columns(agent_version: "0.1.0", heartbeat_at: 5.seconds.ago, heartbeat_status: "ok")
    described_class.perform_now
    expect(server.reload.heartbeat_status).to eq("ok")
  end

  it "ignores servers without the agent installed" do
    server = create(:server) # agent_version nil
    described_class.perform_now
    expect(server.reload.heartbeat_status).to eq("unknown")
  end

  it "opens a host incident on the down transition, once per outage" do
    server = create(:server)
    server.update_columns(agent_version: "0.2.0", heartbeat_at: 5.minutes.ago, heartbeat_status: "ok")

    2.times { described_class.perform_now }

    incidents = Incident.for_server(server)
    expect(incidents.count).to eq(1)
    expect(incidents.sole.reason).to eq("host_down")
    expect(incidents.sole.resolved_at).to be_nil
  end
end

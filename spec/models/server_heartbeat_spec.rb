# spec/models/server_heartbeat_spec.rb
require "rails_helper"

RSpec.describe Server, "#record_heartbeat!" do
  let(:server) { create(:server) }

  it "stores vitals, timestamps the beat, and marks the host ok" do
    server.record_heartbeat!(vitals: { "docker" => "ok", "disk_used_pct" => 42.0 }, agent_version: "0.1.0")
    expect(server.reload).to have_attributes(
      heartbeat_status: "ok", agent_version: "0.1.0",
      vitals: hash_including("disk_used_pct" => 42.0)
    )
    expect(server.heartbeat_at).to be_within(2.seconds).of(Time.current)
  end

  it "marks the host degraded when docker is down" do
    server.record_heartbeat!(vitals: { "docker" => "down", "disk_used_pct" => 10.0 }, agent_version: "0.1.0")
    expect(server.reload.heartbeat_status).to eq("degraded")
  end

  it "marks the host degraded when disk crosses the threshold" do
    server.record_heartbeat!(vitals: { "docker" => "ok", "disk_used_pct" => 91.5 }, agent_version: "0.1.0")
    expect(server.reload.heartbeat_status).to eq("degraded")
  end

  it "emails the founder when a down host starts beating again" do
    server.update_columns(heartbeat_status: "down", agent_version: "0.1.0")
    expect {
      server.record_heartbeat!(vitals: { "docker" => "ok" }, agent_version: "0.1.0")
    }.to have_enqueued_mail(OpsMailer, :host_recovered)
  end

  it "sends a degraded-flavored recovery when a down host resumes degraded" do
    server.update_columns(heartbeat_status: "down", agent_version: "0.1.0")
    expect {
      server.record_heartbeat!(vitals: { "docker" => "ok", "disk_used_pct" => 95.0 }, agent_version: "0.1.0")
    }.to have_enqueued_mail(OpsMailer, :host_recovered)
    expect(server.reload.heartbeat_status).to eq("degraded")
  end

  describe "#heartbeat_stale?" do
    it "is stale with no beat ever" do
      expect(server.heartbeat_stale?).to be(true)
    end

    it "is stale past HEARTBEAT_DOWN_AFTER" do
      server.update_columns(heartbeat_at: 61.seconds.ago)
      expect(server.heartbeat_stale?).to be(true)
    end

    it "is fresh inside the window" do
      server.update_columns(heartbeat_at: 10.seconds.ago)
      expect(server.heartbeat_stale?).to be(false)
    end
  end

  describe "#pending_build_deploys" do
    it "returns only this server's unclaimed wokkud builds still in building" do
      server = create(:server)
      app = create(:app_record, server: server)
      pending = create(:deploy, app_record: app, status: :building, builder: "wokkud")
      create(:deploy, app_record: app, status: :building, builder: "wokkud", build_picked_up_at: Time.current) # claimed
      create(:deploy, app_record: app, status: :building) # dokku build
      create(:deploy, app_record: app, status: :succeeded, builder: "wokkud") # terminal
      other_app = create(:app_record) # different server
      create(:deploy, app_record: other_app, status: :building, builder: "wokkud")

      expect(server.pending_build_deploys).to contain_exactly(pending)
    end
  end

  it "closes the open host incident on the recovery beat" do
    server = create(:server)
    server.update_columns(agent_version: "0.2.0", heartbeat_status: "down")
    incident = Incident.open!(subject: server, reason: "host_down")

    server.record_heartbeat!(vitals: { "docker" => "ok", "disk_used_pct" => 10.0 })

    expect(incident.reload.resolved_at).to be_present
  end

  it "still sends the recovery mail when resolving the incident raises" do
    server = create(:server)
    server.update_columns(agent_version: "0.2.0", heartbeat_status: "down")
    incident = Incident.open!(subject: server, reason: "host_down")
    allow(Incident).to receive(:open_for).and_raise(ActiveRecord::StaleObjectError)

    expect {
      server.record_heartbeat!(vitals: { "docker" => "ok", "disk_used_pct" => 10.0 })
    }.to have_enqueued_mail(OpsMailer, :host_recovered)
    expect(incident.reload.resolved_at).to be_nil
  end

  describe "managed-service stats ingestion (Task 12)" do
    it "ingests per-service stats from vitals" do
      db = create(:database_service, server: server, wokkud_managed: true)
      server.record_heartbeat!(vitals: {
        "docker" => "ok",
        "services" => [ { "name" => db.name, "db_bytes" => 123, "mem_used_mb" => 45 } ]
      })
      expect(db.reload.live_db_bytes).to eq(123)
      expect(db.live_mem_used_mb).to eq(45)
      expect(db.live_metrics_at).to be_present
    end

    it "ignores services that are not wokkud_managed on this server" do
      db = create(:database_service, server: server, wokkud_managed: false)
      server.record_heartbeat!(vitals: {
        "docker" => "ok",
        "services" => [ { "name" => db.name, "db_bytes" => 123, "mem_used_mb" => 45 } ]
      })
      expect(db.reload.live_db_bytes).to be_nil
    end

    it "does not fail the heartbeat when service stats blow up" do
      create(:database_service, server: server, wokkud_managed: true)
      allow_any_instance_of(ActiveRecord::Relation).to receive(:update_all).and_raise(StandardError, "boom")

      expect {
        server.record_heartbeat!(vitals: { "docker" => "ok", "services" => [ { "name" => "whatever" } ] })
      }.not_to raise_error
      expect(server.reload.heartbeat_status).to eq("ok")
    end

    it "completes core heartbeat even when service stats loop raises — rescue scope is narrowed" do
      # Verify that when stats loop raises, the core write (update_columns) has
      # already persisted heartbeat_at/heartbeat_status/vitals, and the method
      # returns normally. The rescue only wraps the stats loop, not the core.
      create(:database_service, server: server, wokkud_managed: true)
      allow_any_instance_of(ActiveRecord::Relation).to receive(:update_all).and_raise(StandardError, "stats boom")

      old_heartbeat_at = server.heartbeat_at
      server.record_heartbeat!(vitals: { "docker" => "ok", "disk_used_pct" => 42.0, "services" => [ { "name" => "whatever" } ] })

      server.reload
      expect(server.heartbeat_status).to eq("ok")
      expect(server.heartbeat_at).to be_after(old_heartbeat_at || 1.minute.ago)
      expect(server.vitals).to include("disk_used_pct" => 42.0)
    end

    it "propagates core-write failures — they are not swallowed by stats rescue" do
      # Verify that if the core update_columns fails, the exception propagates
      # and is not caught by the narrow rescue around the stats loop.
      create(:database_service, server: server, wokkud_managed: true)
      allow(server).to receive(:update_columns).and_raise(ActiveRecord::ReadOnlyRecord, "read-only")

      expect {
        server.record_heartbeat!(vitals: { "docker" => "ok", "services" => [] })
      }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end
  end
end

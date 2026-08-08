require "rails_helper"

RSpec.describe "Api::V1::Agent::Heartbeats" do
  let(:server) { create(:server) }
  let(:headers) { { "Authorization" => "Bearer #{server.ingest_token}", "CONTENT_TYPE" => "application/json" } }

  it "records the beat and echoes the computed status" do
    post "/api/v1/agent/heartbeat",
         params: { vitals: { docker: "ok", disk_used_pct: 40.0, mem_total_mb: 8192 }, agent_version: "0.1.0" }.to_json,
         headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include("status" => "ok")
    expect(server.reload).to have_attributes(heartbeat_status: "ok", agent_version: "0.1.0")
    expect(server.vitals["mem_total_mb"]).to eq(8192)
  end

  it "always carries the router config version" do
    allow(Wokku.config).to receive(:owned_domains).and_return([ "wokku.app" ])
    post "/api/v1/agent/heartbeat",
         params: { vitals: { docker: "ok", disk_used_pct: 40.0 } }.to_json,
         headers: headers
    expect(response.parsed_body["router_config_version"])
      .to eq(Routers::ConfigBuilder.new(server).version)
  end

  it "omits router_config_version but keeps the rest of the payload when ConfigBuilder blows up" do
    allow(Routers::ConfigBuilder).to receive(:new).and_raise(StandardError, "boom")
    server.update!(wokkud_builds_enabled: true)
    app = create(:app_record, server: server)
    pending = create(:deploy, app_record: app, status: :building, builder: "wokkud")

    post "/api/v1/agent/heartbeat",
         params: { vitals: { docker: "ok", disk_used_pct: 40.0 } }.to_json,
         headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include("status" => "ok", "pending_build_ids" => [ pending.id ])
    expect(response.parsed_body).not_to have_key("router_config_version")
  end

  it "rejects a bad token" do
    post "/api/v1/agent/heartbeat",
         params: { vitals: { docker: "ok" } }.to_json,
         headers: headers.merge("Authorization" => "Bearer wrong")
    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects a missing vitals payload" do
    post "/api/v1/agent/heartbeat", params: {}.to_json, headers: headers
    expect(response).to have_http_status(:bad_request)
  end

  describe "build pickup (Phase 4c)" do
    let(:beat_params) { { vitals: { docker: "ok", disk_used_pct: 40.0 } }.to_json }

    it "lists pending wokkud builds when the server flag is on" do
      server.update!(wokkud_builds_enabled: true)
      app = create(:app_record, server: server)
      pending = create(:deploy, app_record: app, status: :building, builder: "wokkud")

      post "/api/v1/agent/heartbeat", params: beat_params, headers: headers
      expect(response.parsed_body["pending_build_ids"]).to eq([ pending.id ])
    end

    it "omits the key when the flag is off, even with pending rows" do
      server.update!(wokkud_builds_enabled: false) # model default is now true
      app = create(:app_record, server: server)
      create(:deploy, app_record: app, status: :building, builder: "wokkud")

      post "/api/v1/agent/heartbeat", params: beat_params, headers: headers
      expect(response.parsed_body).not_to have_key("pending_build_ids")
    end

    it "omits the key when there is nothing pending" do
      server.update!(wokkud_builds_enabled: true)
      post "/api/v1/agent/heartbeat", params: beat_params, headers: headers
      expect(response.parsed_body).not_to have_key("pending_build_ids")
    end
  end

  describe "cron_config_version piggyback (Track B B3)" do
    it "carries cron_config_version when the server is cron-flagged" do
      server.update!(wokkud_cron_enabled: true)
      post "/api/v1/agent/heartbeat", params: { vitals: { docker: "ok" } },
           headers: { "Authorization" => "Bearer #{server.ingest_token}" }, as: :json
      expect(response.parsed_body["cron_config_version"]).to match(/\A[0-9a-f]{64}\z/)
    end

    it "omits the key when unflagged" do
      server.update!(wokkud_cron_enabled: false) # model default is now true
      post "/api/v1/agent/heartbeat", params: { vitals: { docker: "ok" } },
           headers: { "Authorization" => "Bearer #{server.ingest_token}" }, as: :json
      expect(response.parsed_body).not_to have_key("cron_config_version")
    end

    it "omits the key but keeps the rest of the payload when ConfigBuilder blows up" do
      allow(Cron::ConfigBuilder).to receive(:new).and_raise(StandardError, "boom")
      server.update!(wokkud_cron_enabled: true)
      post "/api/v1/agent/heartbeat", params: { vitals: { docker: "ok" } },
           headers: { "Authorization" => "Bearer #{server.ingest_token}" }, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("status" => "ok")
      expect(response.parsed_body).not_to have_key("cron_config_version")
    end
  end

  describe "pending_service_op_ids piggyback" do
    it "is omitted when wokkud_services_enabled is false" do
      server.update!(wokkud_services_enabled: false) # model default is now true
      create(:service_op, server: server)
      post "/api/v1/agent/heartbeat",
        params: { vitals: { docker: "ok" } },
        headers: { "Authorization" => "Bearer #{server.ingest_token}" }
      expect(response.parsed_body).not_to have_key("pending_service_op_ids")
    end

    it "carries pending op ids when enabled" do
      server.update!(wokkud_services_enabled: true)
      op = create(:service_op, server: server)
      create(:service_op, server: server, status: :claimed)
      post "/api/v1/agent/heartbeat",
        params: { vitals: { docker: "ok" } },
        headers: { "Authorization" => "Bearer #{server.ingest_token}" }
      expect(response.parsed_body["pending_service_op_ids"]).to eq([ op.id ])
    end
  end
end

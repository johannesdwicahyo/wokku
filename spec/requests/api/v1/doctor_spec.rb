require "rails_helper"

RSpec.describe "Api::V1::Doctor", type: :request do
  let(:plan) { create(:plan, :free) }
  let(:team) { create(:team, plan: plan) }
  let(:user) { create(:user, plan: create(:plan, :pro)) }
  let(:headers) { api_v1_headers(user) }

  before do
    create(:team_membership, user: user, team: team, role: :admin)
  end

  describe "GET /api/v1/doctor" do
    it "requires authentication" do
      get "/api/v1/doctor"

      expect(response).to have_http_status(:unauthorized)
    end

    it "returns an ok/healthy report when everything is fine" do
      server = create(:server, team: team, heartbeat_status: "ok", heartbeat_at: 10.seconds.ago, agent_version: "1.0.0")
      server.reload
      app_record = create(:app_record, team: team, server: server, status: :running)
      create(:deploy, :succeeded, app_record: app_record, finished_at: 5.minutes.ago)

      get "/api/v1/doctor", headers: headers

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["status"]).to eq("ok")

      auth_check = body["checks"].find { |c| c["name"] == "auth" }
      expect(auth_check["status"]).to eq("ok")
      expect(auth_check["detail"]).to eq("token valid for #{user.email} (plan: pro)")

      client_check = body["checks"].find { |c| c["name"] == "client" }
      expect(client_check["status"]).to eq("ok")

      hosts_check = body["checks"].find { |c| c["name"] == "hosts" }
      expect(hosts_check["status"]).to eq("ok")
      expect(hosts_check["hosts"]).to eq(
        [ { "name" => server.name, "heartbeat_status" => "ok", "heartbeat_at" => server.heartbeat_at.as_json } ]
      )

      apps_check = body["checks"].find { |c| c["name"] == "apps" }
      expect(apps_check["status"]).to eq("ok")
      app_entry = apps_check["apps"].first
      expect(app_entry["name"]).to eq(app_record.name)
      expect(app_entry["status"]).to eq("running")
      expect(app_entry["host_status"]).to eq("ok")
      expect(app_entry["last_deploy"]["status"]).to eq("succeeded")
      expect(app_entry["recent_crashes_24h"]).to eq(0)

      expect(body["hints"]).to eq([])
    end

    it "reports a crashed app with a CrashEvent-derived hint and flips status to issues" do
      server = create(:server, team: team, heartbeat_status: "ok", heartbeat_at: 10.seconds.ago, agent_version: "1.0.0")
      app_record = create(:app_record, team: team, server: server, status: :crashed)
      create(:crash_event, app_record: app_record, exit_code: 137, oom_killed: true, exited_at: 2.minutes.ago)
      create(:crash_event, app_record: app_record, exit_code: 1, oom_killed: false, exited_at: 1.hour.ago)

      get "/api/v1/doctor", headers: headers

      body = response.parsed_body
      expect(body["status"]).to eq("issues")

      apps_check = body["checks"].find { |c| c["name"] == "apps" }
      expect(apps_check["status"]).to eq("warn")
      expect(apps_check["apps"].first["recent_crashes_24h"]).to eq(2)

      expect(body["hints"]).to include(
        "app #{app_record.name} is crashed — last CrashEvent exit 137 (OOM); see /apps/#{app_record.name}/logs"
      )
    end

    it "reports a down host and flips status to issues" do
      server = create(:server, team: team, heartbeat_status: "down", heartbeat_at: 5.minutes.ago, agent_version: "1.0.0")
      create(:app_record, team: team, server: server, status: :running)

      get "/api/v1/doctor", headers: headers

      body = response.parsed_body
      expect(body["status"]).to eq("issues")

      hosts_check = body["checks"].find { |c| c["name"] == "hosts" }
      expect(hosts_check["status"]).to eq("error")
      expect(hosts_check["hosts"].first["heartbeat_status"]).to eq("down")
      expect(hosts_check["detail"]).to include("stopped responding")

      expect(body["hints"]).to include(
        "host #{server.name} stopped responding (last beat 5m ago) — apps on it may be unreachable"
      )
    end

    it "reports a degraded (not down) host with disk-specific wording and flips status to issues" do
      server = create(
        :server, team: team, heartbeat_status: "degraded", heartbeat_at: 10.seconds.ago,
        agent_version: "1.0.0", vitals: { "docker" => "ok", "disk_used_pct" => 93.4 }
      )
      create(:app_record, team: team, server: server, status: :running)

      get "/api/v1/doctor", headers: headers

      body = response.parsed_body
      expect(body["status"]).to eq("issues")

      hosts_check = body["checks"].find { |c| c["name"] == "hosts" }
      expect(hosts_check["status"]).to eq("error")
      expect(hosts_check["hosts"].first["heartbeat_status"]).to eq("degraded")
      expect(hosts_check["detail"]).to include("degraded — disk 93% full")

      expect(body["hints"]).to include(
        "host #{server.name} is degraded (disk 93% full) — deploys may fail until it recovers"
      )
    end

    it "treats an agent-less server as ok-ish with a 'no agent installed' detail" do
      server = create(:server, team: team, heartbeat_status: "unknown", heartbeat_at: nil, agent_version: nil)
      create(:app_record, team: team, server: server, status: :running)

      get "/api/v1/doctor", headers: headers

      body = response.parsed_body
      expect(body["status"]).to eq("ok")

      hosts_check = body["checks"].find { |c| c["name"] == "hosts" }
      expect(hosts_check["status"]).to eq("ok")
      expect(hosts_check["detail"]).to include("no agent installed")
      expect(body["hints"]).to eq([])
    end

    it "flags an outdated client with a warn status and a hint, without flipping overall status" do
      server = create(:server, team: team, heartbeat_status: "ok", heartbeat_at: 10.seconds.ago, agent_version: "1.0.0")
      create(:app_record, team: team, server: server, status: :running)

      get "/api/v1/doctor", headers: headers.merge("X-Wokku-Client" => "cli", "X-Wokku-Client-Version" => "0.4.0")

      body = response.parsed_body
      expect(body["status"]).to eq("ok")

      client_check = body["checks"].find { |c| c["name"] == "client" }
      expect(client_check["status"]).to eq("warn")
      expect(client_check["detail"]).to eq("cli 0.4.0 (min 0.5.0)")

      expect(body["hints"]).to include("cli client 0.4.0 is outdated (min 0.5.0); upgrade recommended")
    end

    it "limits apps to 50 and scopes to the current user's teams only" do
      server = create(:server, team: team)
      create_list(:app_record, 2, team: team, server: server)

      other_team = create(:team)
      other_server = create(:server, team: other_team)
      create(:app_record, team: other_team, server: other_server)

      get "/api/v1/doctor", headers: headers

      body = response.parsed_body
      apps_check = body["checks"].find { |c| c["name"] == "apps" }
      expect(apps_check["apps"].length).to eq(2)

      hosts_check = body["checks"].find { |c| c["name"] == "hosts" }
      expect(hosts_check["hosts"].map { |h| h["name"] }).to contain_exactly(server.name)
    end
  end
end

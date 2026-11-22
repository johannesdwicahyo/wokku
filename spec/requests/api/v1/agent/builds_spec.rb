# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

RSpec.describe "Api::V1::Agent::Builds" do
  let(:server)  { create(:server, wokkud_builds_enabled: true) }
  let(:app_record)     { create(:app_record, server: server) }
  let(:deploy)  { create(:deploy, app_record: app_record, status: :building, builder: "wokkud", archive_key: "deploy-archives/#{app_record.id}/src.tar.gz") }
  let(:headers) { { "Authorization" => "Bearer #{server.ingest_token}", "CONTENT_TYPE" => "application/json" } }

  before do
    store = instance_double(Wokku::Providers::LocalBackupStore, presigned_get: "https://r2.example.com/signed")
    allow(Wokku.config).to receive(:backup_store).and_return(store)
    allow(DeployChannel).to receive(:broadcast_to)
  end

  describe "claim" do
    it "returns the build payload and stamps build_picked_up_at" do
      post "/api/v1/agent/builds/#{deploy.id}/claim", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq(
        "app_name" => app_record.name,
        "archive_url" => "https://r2.example.com/signed",
        "push_ref" => "127.0.0.1:5000/wokku/#{app_record.name}:#{deploy.id}",
        "timeout_seconds" => Deploys::BuildAndConverge.build_timeout.to_i
      )
      expect(deploy.reload.build_picked_up_at).to be_present
    end

    it "falls back to the signed local-serve archive URL when the store can't presign" do
      Dir.mktmpdir do |dir|
        stub_const("ENV", ENV.to_h.merge("WOKKU_BACKUP_PATH" => dir))
        allow(Wokku.config).to receive(:backup_store).and_return(Wokku::Providers::LocalBackupStore.new)

        post "/api/v1/agent/builds/#{deploy.id}/claim", headers: headers
        expect(response).to have_http_status(:ok)
        url = response.parsed_body["archive_url"]
        expect(url).to include("/api/v1/agent/archive?token=")

        # And the endpoint the URL points at actually serves the bytes.
        archive_path = File.join(dir, deploy.archive_key)
        FileUtils.mkdir_p(File.dirname(archive_path))
        File.write(archive_path, "tarball-bytes")
        get URI(url).request_uri
        expect(response).to have_http_status(:ok)
        expect(response.body).to eq("tarball-bytes")
      end
    end

    it "404s the archive endpoint on a bad token" do
      get "/api/v1/agent/archive", params: { token: "forged" }
      expect(response).to have_http_status(:not_found)
    end

    it "409s an already-claimed build" do
      deploy.update!(build_picked_up_at: Time.current)
      post "/api/v1/agent/builds/#{deploy.id}/claim", headers: headers
      expect(response).to have_http_status(:conflict)
    end

    it "404s a deploy belonging to another server" do
      foreign = create(:deploy, status: :building, builder: "wokkud")
      post "/api/v1/agent/builds/#{foreign.id}/claim", headers: headers
      expect(response).to have_http_status(:not_found)
    end

    it "404s a non-wokkud deploy" do
      dokku_deploy = create(:deploy, app_record: app_record, status: :building)
      post "/api/v1/agent/builds/#{dokku_deploy.id}/claim", headers: headers
      expect(response).to have_http_status(:not_found)
    end

    it "410s a terminal deploy (job already timed out or finished)" do
      deploy.update!(status: :failed)
      post "/api/v1/agent/builds/#{deploy.id}/claim", headers: headers
      expect(response).to have_http_status(:gone)
    end

    it "rejects a bad token" do
      post "/api/v1/agent/builds/#{deploy.id}/claim", headers: headers.merge("Authorization" => "Bearer wrong")
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "log" do
    it "appends the chunk to deploy.log and broadcasts it" do
      deploy.update!(log: "existing\n")
      post "/api/v1/agent/builds/#{deploy.id}/log",
           params: { chunk: "step 1/4 : FROM ruby\n" }.to_json, headers: headers
      expect(response).to have_http_status(:ok)
      expect(deploy.reload.log).to eq("existing\nstep 1/4 : FROM ruby\n")
      expect(DeployChannel).to have_received(:broadcast_to)
        .with(deploy, { type: "log", data: "step 1/4 : FROM ruby\n" })
    end

    it "400s an empty chunk" do
      post "/api/v1/agent/builds/#{deploy.id}/log", params: {}.to_json, headers: headers
      expect(response).to have_http_status(:bad_request)
    end

    it "410s a late chunk once the deploy is terminal, without touching the log" do
      deploy.update!(status: :succeeded, log: "final\n")
      post "/api/v1/agent/builds/#{deploy.id}/log",
           params: { chunk: "straggler\n" }.to_json, headers: headers
      expect(response).to have_http_status(:gone)
      expect(deploy.reload.log).to eq("final\n")
    end

    it "404s a deploy belonging to another server" do
      foreign = create(:deploy, status: :building, builder: "wokkud")
      post "/api/v1/agent/builds/#{foreign.id}/log",
           params: { chunk: "x\n" }.to_json, headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "report" do
    it "stamps build_finished_at on success" do
      post "/api/v1/agent/builds/#{deploy.id}/report",
           params: { status: "succeeded" }.to_json, headers: headers
      expect(response).to have_http_status(:ok)
      expect(deploy.reload).to have_attributes(build_error: nil)
      expect(deploy.build_finished_at).to be_present
    end

    it "stores the error on failure" do
      post "/api/v1/agent/builds/#{deploy.id}/report",
           params: { status: "failed", error: "nixpacks: exit 1" }.to_json, headers: headers
      expect(deploy.reload.build_error).to eq("nixpacks: exit 1")
      expect(deploy.build_finished_at).to be_present
    end

    context "when wokkud's relay scan blocked the build" do
      let(:blocked) { "blocked by relay scan: start.sh (xtls/xray-core) — VPN/proxy relays are not allowed (Terms of Service §3)" }

      before { ENV["ADMIN_EMAIL"] = "ops@example.com" }
      after { ENV.delete("ADMIN_EMAIL") }

      it "flags the app and emails the operator" do
        expect {
          post "/api/v1/agent/builds/#{deploy.id}/report", params: { status: "failed", error: blocked }.to_json, headers: headers
        }.to change { ActionMailer::Base.deliveries.size }.by(1)
        expect(app_record.reload.relay_flagged_at).to be_present
        expect(ActionMailer::Base.deliveries.last.body.to_s).to include(app_record.name, "xtls/xray-core")
      end

      it "suspends the owner when the repo owner is already banned" do
        create(:user, abuse_suspended_at: 1.day.ago, abuse_repo_owners: %w[relay-org])
        app_record.update!(git_repo_full_name: "relay-org/innocent-name")
        allow(Lifecycle::Ops).to receive(:converge!)
        post "/api/v1/agent/builds/#{deploy.id}/report", params: { status: "failed", error: blocked }.to_json, headers: headers
        expect(app_record.team.owner.reload.abuse_suspended?).to be(true)
        expect(ActionMailer::Base.deliveries.last.body.to_s).to include("AUTO-SUSPENDED")
      end
    end

    it "persists the formation when the agent reports one" do
      post "/api/v1/agent/builds/#{deploy.id}/report",
           params: { status: "succeeded", formation: { "web" => "node bin/www", "worker" => "bundle exec sidekiq" } }.to_json,
           headers: headers
      expect(response).to have_http_status(:ok)
      expect(deploy.reload.formation_json).to eq("web" => "node bin/www", "worker" => "bundle exec sidekiq")
    end

    it "leaves formation_json nil when the agent's report omits it (old agents)" do
      post "/api/v1/agent/builds/#{deploy.id}/report",
           params: { status: "succeeded" }.to_json, headers: headers
      expect(response).to have_http_status(:ok)
      expect(deploy.reload.formation_json).to be_nil
    end

    it "skips a non-object formation (array) without failing the build report" do
      post "/api/v1/agent/builds/#{deploy.id}/report",
           params: { status: "succeeded", formation: [ "node bin/www" ] }.to_json, headers: headers
      expect(response).to have_http_status(:ok)
      expect(deploy.reload.formation_json).to be_nil
    end

    it "skips a formation with non-string values (nested hash)" do
      post "/api/v1/agent/builds/#{deploy.id}/report",
           params: { status: "succeeded", formation: { "web" => { "cmd" => "x" } } }.to_json, headers: headers
      expect(response).to have_http_status(:ok)
      expect(deploy.reload.formation_json).to be_nil
    end

    it "410s once the deploy is terminal (raced fallback/timeout — report ignored)" do
      deploy.update!(status: :timed_out)
      post "/api/v1/agent/builds/#{deploy.id}/report",
           params: { status: "succeeded" }.to_json, headers: headers
      expect(response).to have_http_status(:gone)
      expect(deploy.reload.build_finished_at).to be_nil
    end

    it "404s a deploy belonging to another server" do
      foreign = create(:deploy, status: :building, builder: "wokkud")
      post "/api/v1/agent/builds/#{foreign.id}/report",
           params: { status: "succeeded" }.to_json, headers: headers
      expect(response).to have_http_status(:not_found)
      expect(foreign.reload.build_finished_at).to be_nil
    end
  end
end

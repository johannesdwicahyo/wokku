require "rails_helper"

RSpec.describe "Api::V1::Agent::Events" do
  # NOTE: don't name this `let(:app)` — `app` is the Rack-app accessor
  # used by Rack::Test internally (see spec/requests/api/v1/logs/ingest_spec.rb).
  let(:team)       { create(:team) }
  let(:server)     { create(:server, team: team) }
  let!(:app_record) { create(:app_record, name: "myapp", server: server, team: team) }
  let(:headers)    { { "Authorization" => "Bearer #{server.ingest_token}", "CONTENT_TYPE" => "application/json" } }

  def post_die(container: "myapp.web.1", exit_code: 137, oom: true)
    post "/api/v1/agent/events",
         params: { events: [ {
           type: "container.died", container: container, container_id: "abc123",
           exit_code: exit_code, oom_killed: oom,
           exited_at: "2026-07-04T12:00:00Z", log_excerpt: "FATAL: out of memory"
         } ] }.to_json,
         headers: headers
  end

  # test env uses :null_store; give the request a real cache so the
  # debounce (Rails.cache.write/read) actually persists across requests,
  # same technique as spec/jobs/crash_loop_detector_job_spec.rb.
  before do
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
  end

  it "stores a CrashEvent for a container death" do
    expect { post_die }.to change(CrashEvent, :count).by(1)
    crash = CrashEvent.last
    expect(crash).to have_attributes(
      app_record_id: app_record.id, container_id: "abc123", exit_code: 137,
      oom_killed: true, log_excerpt: "FATAL: out of memory"
    )
    expect(response.parsed_body).to eq("ingested" => 1)
  end

  it "ignores clean exits and deploy-cycle SIGTERMs" do
    expect { post_die(exit_code: 0) }.not_to change(CrashEvent, :count)
    expect { post_die(exit_code: 143) }.not_to change(CrashEvent, :count)
  end

  it "ignores containers that do not map to an app" do
    expect { post_die(container: "dokku-shared-postgres.svc") }.not_to change(CrashEvent, :count)
  end

  # I9: Swarm task containers (wokku-<app>-<proc>.<slot>.<taskid>) can't be
  # name-parsed back to an app — the wokku.app label maps them.
  it "maps a Swarm-task death to the app via the wokku.app label" do
    post "/api/v1/agent/events",
         params: { events: [ {
           type: "container.died", app: "myapp",
           container: "wokku-myapp-web.1.abc123xyz", container_id: "swarmcid",
           exit_code: 137, oom_killed: true, exited_at: "2026-07-04T12:00:00Z"
         } ] }.to_json,
         headers: headers
    expect(CrashEvent.last&.app_record_id).to eq(app_record.id)
  end

  it "ignores crash events missing container_id" do
    expect {
      post "/api/v1/agent/events",
           params: { events: [ {
             type: "container.died", container: "myapp.web.1",
             exit_code: 137, oom_killed: false,
             exited_at: "2026-07-04T12:00:00Z", log_excerpt: ""
           } ] }.to_json,
           headers: headers
    }.not_to change(CrashEvent, :count)
    expect(response.parsed_body).to eq("ingested" => 0)
  end

  it "alerts the team once per debounce window" do
    notification_for(team, events: [ "app_crashed" ])

    expect { post_die }.to have_enqueued_job(NotifyJob).exactly(:once)
    # Debounce: a second crash inside the window must not enqueue again.
    clear_enqueued_jobs
    expect { post_die }.not_to have_enqueued_job(NotifyJob)
  end

  it "skips non-hash event entries instead of 500ing" do
    post "/api/v1/agent/events", params: { events: "foo" }.to_json, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq("ingested" => 0)
  end

  it "truncates an oversized log_excerpt to MAX_EXCERPT_BYTES" do
    huge = "x" * (Api::V1::Agent::EventsController::MAX_EXCERPT_BYTES + 1_000)
    post "/api/v1/agent/events",
         params: { events: [ {
           type: "container.died", container: "myapp.web.1", container_id: "abc123",
           exit_code: 137, oom_killed: false,
           exited_at: "2026-07-04T12:00:00Z", log_excerpt: huge
         } ] }.to_json,
         headers: headers
    expect(CrashEvent.last.log_excerpt.bytesize).to eq(Api::V1::Agent::EventsController::MAX_EXCERPT_BYTES)
  end

  it "ignores a death Wokku caused (idle sleep, stop, restart) — no crash row, no alert" do
    Lifecycle::Ops.mark_expected_exit!(app_record, 1.minute)
    expect { post_die(exit_code: 1, oom: false) }.not_to change(CrashEvent, :count)
    expect(response.parsed_body).to eq("ingested" => 0)
  end

  it "ignores a death reported after the app went to sleep" do
    app_record.update!(status: :sleeping)
    expect { post_die(exit_code: 1, oom: false) }.not_to change(CrashEvent, :count)
  end

  it "rejects a bad token" do
    post "/api/v1/agent/events", params: { events: [] }.to_json,
         headers: headers.merge("Authorization" => "Bearer wrong")
    expect(response).to have_http_status(:unauthorized)
  end

  private

  def notification_for(team, events:)
    Notification.create!(team: team, events: events, config: {}, channel: "email")
  end
end

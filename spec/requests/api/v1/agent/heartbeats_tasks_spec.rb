require "rails_helper"

# Track B Phase B5a: the heartbeat REQUEST body gains `tasks` — live Swarm
# task states — which fan out to app_records.live_containers per app.
RSpec.describe "Api::V1::Agent::Heartbeats tasks fan-out" do
  let(:server)  { create(:server) }
  let(:headers) { { "Authorization" => "Bearer #{server.ingest_token}", "CONTENT_TYPE" => "application/json" } }
  let!(:blog)   { create(:app_record, server: server, name: "blog") }
  let!(:shop)   { create(:app_record, server: server, name: "shop") }

  def beat(tasks)
    post "/api/v1/agent/heartbeat",
         params: { vitals: { docker: "ok" }, tasks: tasks }.to_json,
         headers: headers
  end

  it "fans task states out to each named app's live_containers" do
    beat([
      { app: "blog", process: "web",    state: "running", desired_state: "running",
        started_at: "2026-07-16T10:00:00Z", exit_code: 0 },
      { app: "blog", process: "worker", state: "failed",  desired_state: "shutdown", exit_code: 137 },
      { app: "shop", process: "web",    state: "running", desired_state: "running", exit_code: 0 }
    ])
    expect(response).to have_http_status(:ok)

    blog.reload
    expect(blog.live_containers.length).to eq(2)
    expect(blog.live_containers.first).to include(
      "process" => "web", "state" => "running", "desired_state" => "running", "exit_code" => 0
    )
    expect(blog.live_containers.second).to include("process" => "worker", "exit_code" => 137)
    expect(blog.live_containers_at).to be_within(5.seconds).of(Time.current)

    shop.reload
    expect(shop.live_containers.length).to eq(1)
    expect(shop.live_containers.first).to include("process" => "web")
  end

  it "ignores tasks for unknown app names without breaking the beat" do
    beat([ { app: "ghost-app", process: "web", state: "running" } ])
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include("status" => "ok")
    expect(blog.reload.live_containers).to be_nil
  end

  it "does not scope by app name across servers" do
    other = create(:app_record, name: "blog-other")
    beat([ { app: "blog-other", process: "web", state: "running" } ])
    expect(response).to have_http_status(:ok)
    expect(other.reload.live_containers).to be_nil
  end

  it "leaves live_containers untouched when the beat carries no tasks" do
    blog.update_columns(live_containers: [ { "process" => "web" } ], live_containers_at: 1.hour.ago)
    beat(nil)
    expect(response).to have_http_status(:ok)
    expect(blog.reload.live_containers).to eq([ { "process" => "web" } ])
  end

  it "empties live_containers for an app missing from a beat that carried tasks (stopped)" do
    blog.update_columns(live_containers: [ { "process" => "web", "state" => "running" } ], live_containers_at: 1.hour.ago)
    beat([ { app: "shop", process: "web", state: "running" } ])
    expect(blog.reload.live_containers).to eq([])
    expect(blog.live_containers_at).to be_within(5.seconds).of(Time.current)
  end

  it "survives a malformed tasks payload (string instead of array)" do
    post "/api/v1/agent/heartbeat",
         params: { vitals: { docker: "ok" }, tasks: "garbage" }.to_json,
         headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include("status" => "ok")
    expect(server.reload.heartbeat_status).to eq("ok")
  end

  it "survives non-hash task entries mixed into the array" do
    beat([ "junk", 42, { app: "blog", process: "web", state: "running" } ])
    expect(response).to have_http_status(:ok)
    expect(blog.reload.live_containers.length).to eq(1)
  end

  it "stores only the whitelisted task keys" do
    beat([ { app: "blog", process: "web", state: "running", evil: "payload" } ])
    expect(blog.reload.live_containers.first).not_to have_key("evil")
    expect(blog.live_containers.first).not_to have_key("app")
  end
end

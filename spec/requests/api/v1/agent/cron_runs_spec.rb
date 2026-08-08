require "rails_helper"

RSpec.describe "agent cron runs" do
  let(:server)     { create(:server) }
  let(:app_record) { create(:app_record, server: server) }
  let(:task)       { create(:scheduled_task, app_record: app_record) }
  let(:headers) { { "Authorization" => "Bearer #{server.ingest_token}" } }

  it "records batch rows" do
    post "/api/v1/agent/cron_runs",
      params: { runs: [ { task_id: task.id, started_at: Time.current.iso8601, exit_code: 0, log_excerpt: "ok" } ] },
      headers: headers, as: :json
    expect(response.parsed_body).to eq("recorded" => 1)
    expect(task.runs.sole.exit_code).to eq(0)
  end

  it "rejects a bad token" do
    post "/api/v1/agent/cron_runs",
      params: { runs: [ { task_id: task.id, started_at: Time.current.iso8601, exit_code: 0 } ] },
      headers: { "Authorization" => "Bearer nope" }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(task.runs.count).to eq(0)
  end

  it "drops runs for a task whose app lives on another server (no cross-server injection)" do
    other_task = create(:scheduled_task, app_record: create(:app_record, server: create(:server)))
    post "/api/v1/agent/cron_runs",
      params: { runs: [ { task_id: other_task.id, started_at: Time.current.iso8601, exit_code: 0 } ] },
      headers: headers, as: :json
    expect(response.parsed_body).to eq("recorded" => 0)
    expect(other_task.runs.count).to eq(0)
  end
end

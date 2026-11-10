require "rails_helper"

RSpec.describe "Api::V1::Agent::LifecycleOps" do
  let(:op)     { create(:lifecycle_op) }
  let(:server) { op.server }
  let(:headers) { { "Authorization" => "Bearer #{server.ingest_token}" } }

  describe "claim" do
    it "claims a pending op exactly once" do
      post "/api/v1/agent/lifecycle_ops/#{op.id}/claim", headers: headers
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["kind"]).to eq("stack.converge")
      expect(body["app_name"]).to eq(op.app_record.name)
      expect(body["params"]).to eq("image_ref" => "127.0.0.1:5000/wokku/x:abc")
      expect(body["timeout_seconds"]).to eq(600) # stack.converge (B5a)

      post "/api/v1/agent/lifecycle_ops/#{op.id}/claim", headers: headers
      expect(response).to have_http_status(:conflict)
    end

    it "sends per-kind timeouts: stack.remove gets the flat 300, not stack.converge's 600" do
      remove_op = create(:lifecycle_op, kind: "stack.remove")
      post "/api/v1/agent/lifecycle_ops/#{remove_op.id}/claim",
        headers: { "Authorization" => "Bearer #{remove_op.server.ingest_token}" }
      expect(response.parsed_body["timeout_seconds"]).to eq(300)
    end

    it "404s for another server's op" do
      foreign = create(:lifecycle_op)
      post "/api/v1/agent/lifecycle_ops/#{foreign.id}/claim", headers: headers
      expect(response).to have_http_status(:not_found)
    end

    it "410s a terminal op" do
      op.update!(status: :succeeded)
      post "/api/v1/agent/lifecycle_ops/#{op.id}/claim", headers: headers
      expect(response).to have_http_status(:gone)
    end

    it "401s without the token" do
      post "/api/v1/agent/lifecycle_ops/#{op.id}/claim"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "log" do
    it "appends chunks atomically and rejects empties" do
      op.update!(status: :claimed)
      post "/api/v1/agent/lifecycle_ops/#{op.id}/log", params: { chunk: "a" }, headers: headers
      post "/api/v1/agent/lifecycle_ops/#{op.id}/log", params: { chunk: "b" }, headers: headers
      expect(op.reload.log).to eq("ab")
      post "/api/v1/agent/lifecycle_ops/#{op.id}/log", params: { chunk: "" }, headers: headers
      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "report" do
    it "finalizes success with result payload" do
      op.update!(status: :claimed)
      post "/api/v1/agent/lifecycle_ops/#{op.id}/report",
        params: { status: "succeeded", result: { formation: { web: 1 } } },
        headers: headers, as: :json
      expect(op.reload).to be_succeeded
      expect(op.result).to eq("formation" => { "web" => 1 })
      expect(op.finished_at).to be_present
    end

    it "finalizes failure with error + code" do
      op.update!(status: :claimed)
      post "/api/v1/agent/lifecycle_ops/#{op.id}/report",
        params: { status: "failed", error: "boom", error_code: "converge_failed" },
        headers: headers, as: :json
      expect(op.reload).to be_failed
      expect(op.error).to eq("boom")
      expect(op.error_code).to eq("converge_failed")
    end

    it "redacts env on report (mirrors B4 gate 2) — success and failure alike" do
      op.update!(status: :claimed,
                 params: { "env" => { "SECRET" => "x" }, "image_ref" => "r" })
      post "/api/v1/agent/lifecycle_ops/#{op.id}/report",
        params: { status: "succeeded", result: {} }, headers: headers, as: :json
      expect(op.reload.params).to eq("env" => "[REDACTED]", "image_ref" => "r")
    end

    it "redacts per-service env on report but keeps image + command (the restart fallback)" do
      op.update!(status: :claimed,
                 params: { "services" => { "web" => { "image" => "r", "command" => [ "run" ], "env" => { "SECRET" => "x" } } } })
      post "/api/v1/agent/lifecycle_ops/#{op.id}/report",
        params: { status: "succeeded", result: {} }, headers: headers, as: :json
      expect(op.reload.params).to eq("services" => { "web" => { "image" => "r", "command" => [ "run" ], "env" => "[REDACTED]" } })
    end

    it "redacts a stack.run op's params.command on report — baked $VARs carry secrets too" do
      other_app = create(:app_record, server: server)
      run_op = create(:lifecycle_op, kind: "stack.run", server: server, app_record: other_app, status: :claimed,
                                      params: { "image_ref" => "r", "command" => "psql postgres://user:pw@host/db" })
      post "/api/v1/agent/lifecycle_ops/#{run_op.id}/report",
        params: { status: "failed", error: "boom", error_code: "command_failed" },
        headers: headers, as: :json
      expect(run_op.reload.params).to eq("image_ref" => "r", "command" => "[REDACTED]")
    end

    it "410s on late/duplicate report to a settled op" do
      op.update!(status: :succeeded, finished_at: 5.minutes.ago)
      original_finished_at = op.finished_at
      post "/api/v1/agent/lifecycle_ops/#{op.id}/report",
        params: { status: "failed", error: "x" },
        headers: headers, as: :json
      expect(response).to have_http_status(:gone)
      expect(op.reload).to be_succeeded
      expect(op.finished_at).to eq(original_finished_at)
    end
  end

  # C4: gate on the pending ops themselves, not on any flagged app — evict
  # flips wokkud_lifecycle off BEFORE issuing stack.remove, so the remove op
  # must still be announced on a server with no flagged app left.
  describe "heartbeat pickup" do
    it "omits pending_lifecycle_op_ids when nothing is pending" do
      op.update!(status: :claimed)
      post "/api/v1/agent/heartbeat",
        params: { vitals: { docker: "ok" } },
        headers: { "Authorization" => "Bearer #{server.ingest_token}" }, as: :json
      expect(response.parsed_body).not_to have_key("pending_lifecycle_op_ids")
    end

    it "carries a pending op even when NO app on the server is flagged (evict path)" do
      op.update!(status: :pending)
      expect(op.app_record.wokkud_lifecycle).to be(false)
      post "/api/v1/agent/heartbeat",
        params: { vitals: { docker: "ok" } },
        headers: { "Authorization" => "Bearer #{server.ingest_token}" }, as: :json
      expect(response.parsed_body["pending_lifecycle_op_ids"]).to eq([ op.id ])
    end

    it "carries pending lifecycle op ids when an app on the server is flagged" do
      op.app_record.update!(wokkud_lifecycle: true)
      post "/api/v1/agent/heartbeat",
        params: { vitals: { docker: "ok" } },
        headers: { "Authorization" => "Bearer #{server.ingest_token}" }, as: :json
      expect(response.parsed_body["pending_lifecycle_op_ids"]).to eq([ op.id ])
    end
  end

  it "serves a 600s timeout for stack.run on claim" do
    other_app = create(:app_record, server: server)
    run_op = create(:lifecycle_op, kind: "stack.run", server: server, app_record: other_app)
    post "/api/v1/agent/lifecycle_ops/#{run_op.id}/claim", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["timeout_seconds"]).to eq(600)
  end

  it "persists result on a failed report (stack.run output tail)" do
    other_app = create(:app_record, server: server)
    run_op = create(:lifecycle_op, kind: "stack.run", server: server, app_record: other_app, status: :claimed)
    post "/api/v1/agent/lifecycle_ops/#{run_op.id}/report",
      params: {
        status: "failed", error: "command exited 7", error_code: "command_failed",
        result: { exit_code: 7, output: "PG::UndefinedTable" }
      },
      headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    run_op.reload
    expect(run_op).to be_failed
    expect(run_op.error_code).to eq("command_failed")
    expect(run_op.result).to eq("exit_code" => 7, "output" => "PG::UndefinedTable")
  end
end

require "rails_helper"

RSpec.describe "Api::V1::Agent::ServiceOps" do
  let(:op)     { create(:service_op) }
  let(:server) { op.server }
  let(:headers) { { "Authorization" => "Bearer #{server.ingest_token}" } }

  describe "claim" do
    it "claims a pending op exactly once" do
      post "/api/v1/agent/service_ops/#{op.id}/claim", headers: headers
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["kind"]).to eq("service.create")
      expect(body["service"]).to eq(op.database_service.container_name)
      expect(body["params"]).to eq("service_type" => "postgres")
      expect(body["timeout_seconds"]).to eq(600) # service.create: cold image pull headroom (B4 gate 7)

      post "/api/v1/agent/service_ops/#{op.id}/claim", headers: headers
      expect(response).to have_http_status(:conflict)
    end

    # Cross-boundary contract (C1): op.service on the wire must be the exact
    # string wokkud's serviceTypeFromContainerName/serviceCreate/serviceAdopt
    # consume — "dokku.<service_type>.<name>", never the bare DB name. This
    # pins the string both sides now share; the Go tests already assert on
    # "dokku.postgres.mydb" (dedicated_test.go).
    it "sends the wokkud container-name shape, not the bare DB name" do
      dedicated = create(:database_service, service_type: "postgres", name: "mydb", tier_name: "basic")
      cross_op = create(:service_op, database_service: dedicated, server: dedicated.server)

      post "/api/v1/agent/service_ops/#{cross_op.id}/claim",
        headers: { "Authorization" => "Bearer #{dedicated.server.ingest_token}" }

      expect(response.parsed_body["service"]).to eq("dokku.postgres.mydb")
    end

    it "sends per-kind timeouts (B4 gate 7): export gets 900s, not the flat 300" do
      export_op = create(:service_op, kind: "service.export")
      post "/api/v1/agent/service_ops/#{export_op.id}/claim",
        headers: { "Authorization" => "Bearer #{export_op.server.ingest_token}" }
      expect(response.parsed_body["timeout_seconds"]).to eq(900)
    end

    it "404s for another server's op" do
      foreign = create(:service_op)
      post "/api/v1/agent/service_ops/#{foreign.id}/claim", headers: headers
      expect(response).to have_http_status(:not_found)
    end

    it "410s a terminal op" do
      op.update!(status: :succeeded)
      post "/api/v1/agent/service_ops/#{op.id}/claim", headers: headers
      expect(response).to have_http_status(:gone)
    end

    it "401s without the token" do
      post "/api/v1/agent/service_ops/#{op.id}/claim"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "log" do
    it "appends chunks atomically and rejects empties" do
      op.update!(status: :claimed)
      post "/api/v1/agent/service_ops/#{op.id}/log", params: { chunk: "a" }, headers: headers
      post "/api/v1/agent/service_ops/#{op.id}/log", params: { chunk: "b" }, headers: headers
      expect(op.reload.log).to eq("ab")
      post "/api/v1/agent/service_ops/#{op.id}/log", params: { chunk: "" }, headers: headers
      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "report" do
    it "finalizes success with result payload" do
      op.update!(status: :claimed)
      post "/api/v1/agent/service_ops/#{op.id}/report",
        params: { status: "succeeded", result: { image: "postgres:16-alpine" } },
        headers: headers, as: :json
      expect(op.reload).to be_succeeded
      expect(op.result).to eq("image" => "postgres:16-alpine")
      expect(op.finished_at).to be_present
    end

    it "finalizes failure with error + code" do
      op.update!(status: :claimed)
      post "/api/v1/agent/service_ops/#{op.id}/report",
        params: { status: "failed", error: "boom", error_code: "service_create_failed" },
        headers: headers, as: :json
      expect(op.reload).to be_failed
      expect(op.error).to eq("boom")
      expect(op.error_code).to eq("service_create_failed")
    end

    it "redacts secret params on report (B4 gate 2) — success and failure alike" do
      op.update!(status: :claimed,
                 params: { "service_type" => "postgres", "password" => "s3cr3t",
                           "presigned_put_url" => "https://r2/signed", "database" => "mydb" })
      post "/api/v1/agent/service_ops/#{op.id}/report",
        params: { status: "succeeded", result: {} }, headers: headers, as: :json
      expect(op.reload.params).to eq(
        "service_type" => "postgres", "password" => "[REDACTED]",
        "presigned_put_url" => "[REDACTED]", "database" => "mydb"
      )
    end

    it "redacts the DEK on report (B4/B5 gate) — a service.import op's decrypted key must not persist" do
      op.update!(status: :claimed, kind: "service.import",
                 params: { "service_type" => "postgres", "dek" => "s3cr3tdek==", "database" => "mydb" })
      post "/api/v1/agent/service_ops/#{op.id}/report",
        params: { status: "succeeded", result: {} }, headers: headers, as: :json
      expect(op.reload.params).to eq(
        "service_type" => "postgres", "dek" => "[REDACTED]", "database" => "mydb"
      )
    end

    it "410s on late/duplicate report to a settled op" do
      op.update!(status: :succeeded, finished_at: 5.minutes.ago)
      original_finished_at = op.finished_at
      post "/api/v1/agent/service_ops/#{op.id}/report",
        params: { status: "failed", error: "x" },
        headers: headers, as: :json
      expect(response).to have_http_status(:gone)
      expect(op.reload).to be_succeeded
      expect(op.finished_at).to eq(original_finished_at)
    end
  end
end

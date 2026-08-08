require "rails_helper"

RSpec.describe "Api::V1::Runs", type: :request do
  let(:team) { create(:team) }
  let(:user) { create(:user) }
  let(:headers) { api_v1_headers(user) }
  let(:server) { create(:server, team: team) }
  let(:app_record) { create(:app_record, team: team, server: server, wokkud_lifecycle: true) }

  before do
    create(:team_membership, user: user, team: team, role: :member)
  end

  describe "POST /api/v1/apps/:id/run" do
    before do
      create(:deploy, :wokkud, :succeeded, app_record: app_record)
    end

    it "issues a stack.run op and returns 202 with the run id" do
      post "/api/v1/apps/#{app_record.id}/run", params: { command: "bin/rails db:migrate" }, headers: headers

      expect(response).to have_http_status(:accepted)
      op = LifecycleOp.find(response.parsed_body["run_id"])
      expect(op.kind).to eq("stack.run")
      expect(op).to be_pending
    end

    it "400s a blank command" do
      post "/api/v1/apps/#{app_record.id}/run", params: { command: " " }, headers: headers

      expect(response).to have_http_status(:bad_request)
    end

    it "409s when a live op already holds the app's lane" do
      # Real live LifecycleOp row (no stubbing) — this exercises the actual
      # index_lifecycle_ops_one_live_per_app partial unique index collision
      # that Lifecycle::Ops.issue! converts into a typed Busy. This exact
      # site regressed once already on this branch (ec6b607d): the rescue
      # in run_async must map Busy -> :service_busy, not an unmapped 500.
      create(:lifecycle_op, app_record: app_record, server: app_record.server,
             kind: "stack.converge", status: :pending)

      post "/api/v1/apps/#{app_record.id}/run", params: { command: "x" }, headers: headers

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body["error_code"]).to eq("service_busy")
    end
  end

  describe "GET /api/v1/apps/:app_id/runs/:id" do
    it "returns the op's status and result" do
      op = create(:lifecycle_op, app_record: app_record, server: app_record.server,
                  kind: "stack.run", status: :succeeded,
                  result: { "exit_code" => 0, "output" => "done" })

      get "/api/v1/apps/#{app_record.id}/runs/#{op.id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include(
        "status" => "succeeded", "exit_code" => 0, "output" => "done")
    end

    it "404s a non-run op id" do
      op = create(:lifecycle_op, app_record: app_record, server: app_record.server, kind: "stack.converge")

      get "/api/v1/apps/#{app_record.id}/runs/#{op.id}", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end
end

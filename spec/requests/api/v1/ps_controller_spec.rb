# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API::V1::PsController (deep)", type: :request do
  let(:user) { users(:one) }
  let(:app_record) { app_records(:one) }
  let(:plain_token) { api_v1_token_for(user) }
  let(:headers) { { "Authorization" => "Bearer #{plain_token}" } }

  it "show derives the process report from live_containers (no SSH)" do
    app_record.update!(live_containers: [
      { "process" => "web", "state" => "running", "desired_state" => "running" },
      { "process" => "web", "state" => "running", "desired_state" => "running" },
      { "process" => "worker", "state" => "failed", "exit_code" => 1 }
    ])
    get "/api/v1/apps/#{app_record.id}/ps", headers: headers
    expect(response).to have_http_status(:success)
    expect(JSON.parse(response.body)["processes"]).to eq(
      "status_web_1" => "running",
      "status_web_2" => "running",
      "status_worker_1" => "failed"
    )
  end

  it "show returns an empty report when live_containers is empty" do
    app_record.update!(live_containers: [])
    get "/api/v1/apps/#{app_record.id}/ps", headers: headers
    expect(response).to have_http_status(:success)
    expect(JSON.parse(response.body)["processes"]).to eq({})
  end

  it "update rejects non-hash scaling" do
    put "/api/v1/apps/#{app_record.id}/ps", params: { scaling: "invalid" }, headers: headers
    expect(response).to have_http_status(:bad_request)
  end

  it "update rejects missing scaling parameter" do
    put "/api/v1/apps/#{app_record.id}/ps", headers: headers
    expect(response).to have_http_status(:bad_request)
  end

  it "update converges the formation and persists counts" do
    user.plan.update!(box_quotas: { "small" => 10 })
    expect(::Lifecycle::Ops).to receive(:converge!)
      .with(app_record, formation: { "web" => 3, "worker" => 2 }, timeout: 60)
    put "/api/v1/apps/#{app_record.id}/ps",
      params: { scaling: { "web" => 3, "worker" => 2 } },
      headers: headers
    expect(response).to have_http_status(:success)
    expect(app_record.process_scales.find_by(process_type: "web").count).to eq(3)
    expect(app_record.process_scales.find_by(process_type: "worker").count).to eq(2)
  end

  it "update enforces the plan box quota (dashboard-mirrored guard)" do
    user.plan.update!(box_quotas: { "small" => 0 })
    # Quotas resolve through the injected enforcer (OSS null is unlimited).
    allow(Wokku.config.plan_enforcer).to receive(:quota) { |_u, _k, size| user.plan.box_quotas.fetch(size.to_s, 0) }
    expect(::Lifecycle::Ops).not_to receive(:converge!)
    put "/api/v1/apps/#{app_record.id}/ps",
      params: { scaling: { "web" => 3 } },
      headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)["error_code"]).to eq("quota_exceeded")
  end

  it "update blocks horizontal scaling above 1 on a non-scalable tier" do
    user.plan.update!(box_quotas: { "sleeping" => 99 })
    tier = dyno_tiers(:free)
    tier.update!(scalable: false)
    app_record.dyno_allocations.create!(process_type: "web", dyno_tier: tier, count: 1)
    expect(::Lifecycle::Ops).not_to receive(:converge!)
    put "/api/v1/apps/#{app_record.id}/ps",
      params: { scaling: { "web" => 2 } },
      headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    body = JSON.parse(response.body)
    expect(body["error_code"]).to eq("quota_exceeded")
    expect(body["error"]).to match(/doesn't support horizontal scaling/)
  end

  it "update returns 409 service_busy when another op holds the app's lane" do
    user.plan.update!(box_quotas: { "small" => 10 })
    allow(::Lifecycle::Ops).to receive(:converge!).and_raise(::Lifecycle::Ops::Busy.new(app_record))
    put "/api/v1/apps/#{app_record.id}/ps",
      params: { scaling: { "web" => 2 } },
      headers: headers
    expect(response).to have_http_status(:conflict)
    expect(JSON.parse(response.body)["error_code"]).to eq("service_busy")
  end

  it "update returns 422 formation_would_empty when the formation zeroes web implicitly" do
    allow(::Lifecycle::Ops).to receive(:converge!).and_raise(::Lifecycle::Ops::EmptyFormation, "formation omits web")
    put "/api/v1/apps/#{app_record.id}/ps",
      params: { scaling: { "worker" => 1 } },
      headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)["error_code"]).to eq("formation_would_empty")
  end

  it "update returns 502 when the converge op fails on the host" do
    user.plan.update!(box_quotas: { "small" => 10 })
    op = LifecycleOp.new(kind: "stack.converge", error: "boom", error_code: "task_failed")
    allow(::Lifecycle::Ops).to receive(:converge!).and_raise(::Lifecycle::Ops::Failed.new(op))
    put "/api/v1/apps/#{app_record.id}/ps",
      params: { scaling: { "web" => 2 } },
      headers: headers
    expect(response).to have_http_status(:bad_gateway)
    body = JSON.parse(response.body)
    expect(body["error_code"]).to eq("dokku_command_failed")
    expect(body["error"]).to include("boom")
  end
end

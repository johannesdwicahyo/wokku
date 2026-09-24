require "rails_helper"

RSpec.describe "PATCH /api/v1/apps/:id/ps resources", type: :request do
  let(:user)       { users(:one) }
  let(:app_record) { app_records(:one) }
  let(:headers)    { api_v1_headers(user) }

  it "rejects an off-grid shape with 422 and persists nothing" do
    patch "/api/v1/apps/#{app_record.id}/ps", params: { resources: { web: { cpu: "0.3", memory_mb: "512" } } }, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    expect(app_record.dyno_allocations.where.not(cpu: nil)).to be_empty
  end

  it "applies a valid shape" do
    allow(ApplyResourcesJob).to receive(:perform_later)
    patch "/api/v1/apps/#{app_record.id}/ps", params: { resources: { web: { cpu: "0.5", memory_mb: "1024" } } }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(app_record.dyno_allocations.find_by(process_type: "web").memory_mb).to eq(1024)
  end

  it "combines resources with a scaling count for a different process without a synchronous converge (fix round 2)" do
    allow(ApplyResourcesJob).to receive(:perform_later)
    expect(::Lifecycle::Ops).not_to receive(:converge!)
    patch "/api/v1/apps/#{app_record.id}/ps",
      params: { resources: { web: { cpu: "0.5", memory_mb: "1024" } }, scaling: { web: 2, worker: 1 } },
      headers: headers
    expect(response).to have_http_status(:ok)
    expect(app_record.process_scales.find_by(process_type: "web").count).to eq(2)
    expect(app_record.process_scales.find_by(process_type: "worker").count).to eq(1)
    expect(ApplyResourcesJob).to have_received(:perform_later).once
  end

  it "rejects an invalid scaling count for a process not covered by resources (fix round 2)" do
    patch "/api/v1/apps/#{app_record.id}/ps",
      params: { resources: { web: { cpu: "0.5", memory_mb: "1024" } }, scaling: { web: 2, worker: 99 } },
      headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
  end
end

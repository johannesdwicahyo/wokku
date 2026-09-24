require "rails_helper"

RSpec.describe Lifecycle::Ops, ".resources_for" do
  let(:app) { create(:app_record) }

  it "keeps legacy behavior: tier-only web sizes every process" do
    tier = create(:dyno_tier, memory_mb: 1024, cpu_shares: 0.5)
    create(:dyno_allocation, app_record: app, process_type: "web", dyno_tier: tier)
    expect(described_class.resources_for(app, %w[web worker run])).to eq(
      "web" => { memory_mb: 1024, cpu: 0.5 }, "worker" => { memory_mb: 1024, cpu: 0.5 }, "run" => { memory_mb: 1024, cpu: 0.5 }
    )
  end

  it "sizes each process from its own shape" do
    create(:dyno_allocation, app_record: app, process_type: "web", dyno_tier: nil, cpu: 0.5, memory_mb: 1024)
    create(:dyno_allocation, app_record: app, process_type: "worker", dyno_tier: nil, cpu: 0.25, memory_mb: 2048)
    expect(described_class.resources_for(app, %w[web worker])).to eq(
      "web" => { memory_mb: 1024, cpu: 0.5 }, "worker" => { memory_mb: 2048, cpu: 0.25 }
    )
  end

  it "falls back to web's shape for a process with no row (new Procfile entry, run)" do
    create(:dyno_allocation, app_record: app, process_type: "web", dyno_tier: nil, cpu: 1.0, memory_mb: 2048)
    expect(described_class.resources_for(app, %w[clock run])).to eq(
      "clock" => { memory_mb: 2048, cpu: 1.0 }, "run" => { memory_mb: 2048, cpu: 1.0 }
    )
  end

  it "returns empty limits when the app has no allocation at all" do
    expect(described_class.resources_for(app, %w[web])).to eq("web" => {})
  end
end

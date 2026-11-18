require "rails_helper"

RSpec.describe DatabaseProvisioner do
  it "creates a dedicated service with the chosen shape" do
    app = create(:app_record)
    shape = Resources::Shape.new(cpu: 0.5, memory_mb: 1024, disk_gb: 20)
    allow(Services::Ops).to receive(:issue_and_wait!).and_return(double(succeeded?: true, result: {}))
    db = described_class.new(app: app, service_type: "postgres", tier: "basic", creator: app.creator, shape: shape).call
    expect(db.shape).to eq(shape)
    expect(Services::Ops).to have_received(:issue_and_wait!).with(
      hash_including(kind: "service.create", params: hash_including(memory_mb: 1024, cpu: 0.5, max_connections: 80))
    )
  end

  # API/CLI creates (and any caller that passes no shape) used to leave
  # cpu/memory/disk nil — billing skips unshaped dedicated services, so they
  # ran for free (piksa-db & co, 2026-11-18). Fall back to the tier's shape.
  it "gives a dedicated service its tier's shape when the caller passes none" do
    allow(Wokku.config).to receive(:resource_builder?).and_return(true)
    app = create(:app_record)
    allow(Services::Ops).to receive(:issue_and_wait!).and_return(double(succeeded?: true, result: {}))
    db = described_class.new(app: app, service_type: "postgres", tier: "basic", creator: app.creator).call
    expected = Resources::ApplyChange.service_shape_for_tier("postgres", "basic")
    expect(expected).to be_present
    expect(db.reload.shape).to eq(expected)
  end

  it "leaves the shape empty when the resource builder is off (legacy tier pricing)" do
    allow(Wokku.config).to receive(:resource_builder?).and_return(false)
    app = create(:app_record)
    allow(Services::Ops).to receive(:issue_and_wait!).and_return(double(succeeded?: true, result: {}))
    db = described_class.new(app: app, service_type: "postgres", tier: "basic", creator: app.creator).call
    expect(db.reload.cpu).to be_nil
  end
end

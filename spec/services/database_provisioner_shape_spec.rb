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
end

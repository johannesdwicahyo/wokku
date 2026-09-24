require "rails_helper"

RSpec.describe ApplyDatabaseTierJob do
  it "applies the shape (memory + cpu + derived connections) when present" do
    db = create(:database_service, cpu: 0.25, memory_mb: 512, disk_gb: 5)
    allow(Services::Ops).to receive(:issue_and_wait!)
    described_class.perform_now(db.id)
    expect(Services::Ops).to have_received(:issue_and_wait!).with(
      service: db, kind: "service.set_limits", params: { memory_mb: 512, cpu: 0.25, max_connections: 40 }
    )
  end
end

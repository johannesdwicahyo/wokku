require "rails_helper"

RSpec.describe Resources::ResizeService do
  let(:server) { create(:server, vitals: { "mem_total_mb" => 100_000 }) }
  let(:db)     { create(:database_service, server: server, cpu: 0.25, memory_mb: 512, disk_gb: 10) }
  let(:user)   { create(:user) }

  it "grows and enqueues the limits job" do
    expect {
      r = described_class.call(db: db, user: user, shape: Resources::Shape.new(cpu: 0.5, memory_mb: 1024, disk_gb: 20))
      expect(r.ok).to be(true)
    }.to have_enqueued_job(ApplyDatabaseTierJob).with(db.id)
    expect(db.reload.disk_gb).to eq(20)
  end

  it "refuses to shrink disk" do
    r = described_class.call(db: db, user: user, shape: Resources::Shape.new(cpu: 0.25, memory_mb: 512, disk_gb: 5))
    expect(r.ok).to be(false)
    expect(r.error).to match(/only grow/)
    expect(db.reload.disk_gb).to eq(10)
  end

  it "refuses shared services" do
    db.update_columns(shared: true)
    expect(described_class.call(db: db, user: user, shape: Resources::Shape.new(cpu: 0.5, memory_mb: 1024, disk_gb: 20)).ok).to be(false)
  end

  it "refuses when the plan enforcer denies the resize" do
    create(:app_database, database_service: db)
    allow(Wokku.config.plan_enforcer).to receive(:allowed?).and_return(false)
    r = described_class.call(db: db, user: user, shape: Resources::Shape.new(cpu: 0.5, memory_mb: 1024, disk_gb: 20))
    expect(r.ok).to be(false)
    expect(r.error).to match(/limit/)
    expect(db.reload.memory_mb).to eq(512)
  end
end

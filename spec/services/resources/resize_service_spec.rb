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

  # fix round 1: a legacy tier-only service (never given a shape) has
  # disk_gb nil — its floor must be the tier's storage_gb, not 0.
  context "legacy tier-only service (no shape assigned yet)" do
    let(:tier_service) do
      ServiceTier.find_or_create_by!(name: "legacy-basic", service_type: "postgres") do |t|
        t.spec = { "memory_mb" => 256, "storage_gb" => 8 }
      end
      create(:database_service, server: server, tier_name: "legacy-basic", cpu: nil, memory_mb: nil, disk_gb: nil)
    end

    it "refuses a resize that would land below the tier's storage_gb" do
      r = described_class.call(db: tier_service, user: user, shape: Resources::Shape.new(cpu: 0.5, memory_mb: 1024, disk_gb: 5))
      expect(r.ok).to be(false)
      expect(r.error).to match(/only grow/)
      expect(tier_service.reload.disk_gb).to be_nil
    end

    it "allows a resize matching the tier's storage_gb" do
      r = described_class.call(db: tier_service, user: user, shape: Resources::Shape.new(cpu: 0.5, memory_mb: 1024, disk_gb: 8))
      expect(r.ok).to be(true)
      expect(tier_service.reload.disk_gb).to eq(8)
    end
  end

  # fix round 1: an unlinked service (no app yet) must still resolve a
  # billing team via its creator, so the plan enforcer actually runs.
  it "resolves the billing team via the creator when the service isn't linked to any app" do
    creator = create(:user, :with_personal_team)
    team = creator.teams.first
    unlinked_db = create(:database_service, server: server, creator: creator, cpu: 0.25, memory_mb: 512, disk_gb: 10)
    allow(Wokku.config.plan_enforcer).to receive(:allowed?).and_return(true)
    described_class.call(db: unlinked_db, user: user, shape: Resources::Shape.new(cpu: 0.5, memory_mb: 1024, disk_gb: 20))
    expect(Wokku.config.plan_enforcer).to have_received(:allowed?).with(team, :resources, hash_including(:from, :to))
  end
end

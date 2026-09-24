require "rails_helper"

RSpec.describe Resources::ApplyChange do
  let(:server) { create(:server, vitals: { "mem_total_mb" => 100_000 }) }
  let(:user)   { create(:user) }
  let(:app)    { create(:app_record, server: server, creator: user) }

  it "persists per-process shapes + counts and enqueues a converge" do
    result = nil
    expect {
      result = described_class.call(app: app, user: user, processes: {
        "web" => { cpu: "0.5", memory_mb: "1024", count: "2" },
        "worker" => { cpu: "0.25", memory_mb: "512", count: "1" }
      })
    }.to have_enqueued_job(ApplyResourcesJob).with(app.id)
    expect(result.ok).to be(true)
    expect(app.dyno_allocations.find_by(process_type: "web").shape.to_h).to include(cpu: 0.5, memory_mb: 1024)
    expect(app.process_scales.find_by(process_type: "web").count).to eq(2)
  end

  it "switches a process to the free sleeping preset" do
    # global_fixtures loads a "free" dyno_tier (memory_mb 256, sleeps: true)
    # for every spec — matches what this test needs, no factory required.
    described_class.call(app: app, user: user, processes: { "web" => { sleeping: "1", count: "1" } })
    alloc = app.dyno_allocations.find_by(process_type: "web")
    expect(alloc).to be_sleeping
    expect(alloc.cpu).to be_nil
  end

  it "rejects off-grid input without touching the DB" do
    result = described_class.call(app: app, user: user, processes: { "web" => { cpu: "0.3", memory_mb: "512", count: "1" } })
    expect(result.ok).to be(false)
    expect(result.error).to match(/CPU/)
    expect(app.dyno_allocations.count).to eq(0)
  end

  it "rejects when the plan enforcer says no" do
    allow(Wokku.config.plan_enforcer).to receive(:allowed?).and_call_original
    allow(Wokku.config.plan_enforcer).to receive(:allowed?).with(anything, :resources, hash_including(:from, :to)).and_return(false)
    result = described_class.call(app: app, user: user, processes: { "web" => { cpu: "4", memory_mb: "8192", count: "1" } })
    expect(result.ok).to be(false)
    expect(result.error).to match(/limit/)
  end

  it "rejects when the server is full and keeps the old shape" do
    server.update!(vitals: { "mem_total_mb" => 1000 })
    app.dyno_allocations.create!(process_type: "web", count: 1, cpu: 0.25, memory_mb: 256)
    result = described_class.call(app: app, user: user, processes: { "web" => { cpu: "1", memory_mb: "4096", count: "1" } })
    expect(result.ok).to be(false)
    expect(result.error).to match(/capacity/)
    expect(app.dyno_allocations.find_by(process_type: "web").memory_mb).to eq(256)
  end

  it "sets volume disk and refuses negative" do
    expect(described_class.call(app: app, user: user, processes: {}, volume_disk_gb: "10").ok).to be(true)
    expect(app.reload.volume_disk_gb).to eq(10)
    expect(described_class.call(app: app, user: user, processes: {}, volume_disk_gb: "-1").ok).to be(false)
  end

  it "allows a near-limit upsize whose true post-change total stays under 90% (fix round 1)" do
    full_host = create(:server, vitals: { "mem_total_mb" => 10_000 })
    other_app = create(:app_record, server: full_host)
    other_app.dyno_allocations.create!(process_type: "web", count: 1, cpu: 1.0, memory_mb: 5120)
    other_app.process_scales.create!(process_type: "web", count: 1)

    target = create(:app_record, server: full_host, creator: user)
    target.dyno_allocations.create!(process_type: "web", count: 1, cpu: 0.25, memory_mb: 256)
    target.process_scales.create!(process_type: "web", count: 1)

    # True post-change total: 5120 (other app) + 2048 (this resize) = 7168 < 9000 (90% of 10_000).
    result = described_class.call(app: target, user: user, processes: { "web" => { cpu: "0.5", memory_mb: "2048", count: "1" } })

    expect(result.ok).to be(true)
    expect(target.dyno_allocations.find_by(process_type: "web").memory_mb).to eq(2048)
  end

  it "allows resizing off a legacy tier-only allocation (no shape yet) when the true total stays under 90% (fix round 1)" do
    small_host = create(:server, vitals: { "mem_total_mb" => 3_000 })
    legacy_tier = create(:dyno_tier, memory_mb: 1024, cpu_shares: 0.5, sleeps: false)
    target = create(:app_record, server: small_host, creator: user)
    target.dyno_allocations.create!(process_type: "web", count: 1, dyno_tier: legacy_tier)
    target.process_scales.create!(process_type: "web", count: 1)

    # True post-change total: 1536 < 2700 (90% of 3_000).
    result = described_class.call(app: target, user: user, processes: { "web" => { cpu: "0.5", memory_mb: "1536", count: "1" } })

    expect(result.ok).to be(true)
    expect(target.dyno_allocations.find_by(process_type: "web").memory_mb).to eq(1536)
  end
end

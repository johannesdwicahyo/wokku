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

  it "keeps the current CPU when only memory is given (wokku ps:resize --memory)" do
    described_class.call(app: app, user: user, processes: { "web" => { cpu: "0.5", memory_mb: "1024" } })
    result = described_class.call(app: app, user: user, processes: { "web" => { memory_mb: "2048" } })
    expect(result.ok).to be(true), result.error
    expect(app.dyno_allocations.find_by(process_type: "web").shape.to_h).to include(cpu: 0.5, memory_mb: 2048)
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

  it "sets pending_action when it enqueues the resize job (fix round 2)" do
    described_class.call(app: app, user: user, processes: { "web" => { cpu: "0.5", memory_mb: "1024", count: "1" } })
    expect(app.reload.pending_action).to eq("resize")
  end

  it "does not set pending_action for a volume-only change (fix round 2)" do
    described_class.call(app: app, user: user, processes: {}, volume_disk_gb: "10")
    expect(app.reload.pending_action).to be_nil
  end

  it "does not set pending_action for a not-yet-deployed (created) app (fix round 2)" do
    app.update!(status: :created)
    described_class.call(app: app, user: user, processes: { "web" => { cpu: "0.5", memory_mb: "1024", count: "1" } })
    expect(app.reload.pending_action).to be_nil
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

  describe "free sleeping quota (fix round 1 #2)" do
    let(:quota_user) { create(:user, :with_personal_team) }
    let(:quota_team) { quota_user.teams.first }
    let(:quota_app)  { create(:app_record, server: server, creator: quota_user, team: quota_team) }
    let(:free_tier)  { DynoTier.find_by!(name: "free") }

    def create_sleeping_app!
      a = create(:app_record, server: server, creator: quota_user, team: quota_team)
      a.dyno_allocations.create!(process_type: "web", dyno_tier: free_tier, count: 1)
    end

    def stub_quota(n)
      allow(Wokku.config.plan_enforcer).to receive(:quota).and_call_original
      allow(Wokku.config.plan_enforcer).to receive(:quota).with(quota_user, :box, "sleeping").and_return(n)
    end

    it "rejects a new sleeping allocation when the user is already at quota" do
      stub_quota(3)
      3.times { create_sleeping_app! }
      result = described_class.call(app: quota_app, user: quota_user, processes: { "web" => { sleeping: "1", count: "1" } })
      expect(result.ok).to be(false)
      expect(result.error).to match(/free sleeping apps/)
      expect(quota_app.dyno_allocations.find_by(process_type: "web")).to be_nil
    end

    it "allows a new sleeping allocation when under quota" do
      stub_quota(3)
      2.times { create_sleeping_app! }
      result = described_class.call(app: quota_app, user: quota_user, processes: { "web" => { sleeping: "1", count: "1" } })
      expect(result.ok).to be(true)
    end

    it "does not double-count a process that is already sleeping" do
      stub_quota(1)
      quota_app.dyno_allocations.create!(process_type: "web", dyno_tier: free_tier, count: 1)
      result = described_class.call(app: quota_app, user: quota_user, processes: { "web" => { sleeping: "1", count: "1" } })
      expect(result.ok).to be(true)
    end

    it "never rejects under the OSS null enforcer (Float::INFINITY quota)" do
      5.times { create_sleeping_app! }
      result = described_class.call(app: quota_app, user: quota_user, processes: { "web" => { sleeping: "1", count: "1" } })
      expect(result.ok).to be(true)
    end
  end

  describe ".check_new_shape" do
    it "accepts a valid shape with room" do
      result = described_class.check_new_shape(team: app.team, server: server, shape: Resources::Shape.new(cpu: 0.25, memory_mb: 512))
      expect(result.ok).to be(true)
    end

    it "rejects an off-grid shape without touching capacity" do
      result = described_class.check_new_shape(team: app.team, server: server, shape: Resources::Shape.new(cpu: 0.3, memory_mb: 512))
      expect(result.ok).to be(false)
      expect(result.error).to match(/CPU/)
    end

    it "rejects when the server is full" do
      server.update!(vitals: { "mem_total_mb" => 1000 })
      result = described_class.check_new_shape(team: app.team, server: server, shape: Resources::Shape.new(cpu: 1.0, memory_mb: 4096))
      expect(result.ok).to be(false)
      expect(result.error).to match(/capacity/)
    end

    it "rejects when the plan enforcer says no" do
      allow(Wokku.config.plan_enforcer).to receive(:allowed?).and_call_original
      allow(Wokku.config.plan_enforcer).to receive(:allowed?).with(anything, :resources, hash_including(:from, :to)).and_return(false)
      result = described_class.check_new_shape(team: app.team, server: server, shape: Resources::Shape.new(cpu: 0.25, memory_mb: 512))
      expect(result.ok).to be(false)
      expect(result.error).to match(/limit/)
    end
  end

  describe ".team_allocations" do
    it "includes an unlinked shaped service created by a team member (fix round 1)" do
      member = create(:user, :with_personal_team)
      team = member.teams.first
      unlinked_db = create(:database_service, server: server, creator: member, cpu: 0.25, memory_mb: 512, disk_gb: 5)

      allocations = described_class.team_allocations(team)

      expect(allocations).to include(a_hash_including(service_id: unlinked_db.id, shape: unlinked_db.shape, instances: 1))
    end

    it "counts an unlinked shaped service only toward its billing (first) team, not every team the creator belongs to (fix round 2)" do
      member = create(:user, :with_personal_team)
      first_team = member.teams.first
      other_team = create(:team)
      create(:team_membership, team: other_team, user: member, role: :member)
      unlinked_db = create(:database_service, server: server, creator: member, cpu: 0.25, memory_mb: 512, disk_gb: 5)

      expect(described_class.team_allocations(first_team)).to include(a_hash_including(service_id: unlinked_db.id))
      expect(described_class.team_allocations(other_team)).not_to include(a_hash_including(service_id: unlinked_db.id))
    end
  end
  describe "final review fixes" do
    it "C1: refuses everything when the resource builder is off" do
      allow(Wokku.config).to receive(:resource_builder?).and_return(false)
      r = described_class.call(app: app, user: user, processes: { "web" => { cpu: "0.5", memory_mb: "1024", count: "1" } }, volume_disk_gb: "5")
      expect(r.ok).to be(false)
      expect(r.error).to eq("Custom sizing is not enabled on this server.")
      expect(app.dyno_allocations.count).to eq(0)
      expect(app.reload.volume_disk_gb.to_i).to eq(0)
      c = described_class.check_new_shape(team: app.team, server: server, shape: Resources::Shape.new(cpu: 0.25, memory_mb: 512))
      expect(c.ok).to be(false)
      expect(c.error).to eq("Custom sizing is not enabled on this server.")
    end

    it "C2: rejects web count 0 but allows a non-web process at 0" do
      r = described_class.call(app: app, user: user, processes: { "web" => { cpu: "0.5", memory_mb: "1024", count: "0" } })
      expect(r.ok).to be(false)
      expect(r.error).to eq("Use Stop to stop the app — web can't be scaled to 0 here.")
      ok = described_class.call(app: app, user: user, processes: { "worker" => { cpu: "0.25", memory_mb: "512", count: "0" } })
      expect(ok.ok).to be(true)
    end

    it "I4: rejects more than one sleeping instance" do
      r = described_class.call(app: app, user: user, processes: { "web" => { sleeping: "1", count: "2" } })
      expect(r.ok).to be(false)
      expect(r.error).to eq("Free sleeping apps run a single instance.")
      expect(app.dyno_allocations.count).to eq(0)
    end

    it "M3: turns a missing free DynoTier into a refusal, not an exception" do
      DynoTier.where(name: "free").delete_all
      r = described_class.call(app: app, user: user, processes: { "web" => { sleeping: "1", count: "1" } })
      expect(r.ok).to be(false)
      expect(r.error).to be_present
    end

    it "M2: rejects non-hash processes / process entries" do
      expect(described_class.call(app: app, user: user, processes: "junk").ok).to be(false)
      expect(described_class.call(app: app, user: user, processes: { "web" => "junk" }).ok).to be(false)
    end

    it "I8: a volume-only change shows up in the enforcer's to: with the new disk" do
      seen = nil
      # Other callers (AppRecord#run_allowed?) ask allowed? without from:/to:.
      allow(Wokku.config.plan_enforcer).to receive(:allowed?).and_wrap_original do |m, team, kind, **kw|
        next m.call(team, kind, **kw) unless kind == :resources
        seen = kw[:to]
        true
      end
      described_class.call(app: app, user: user, processes: {}, volume_disk_gb: "7")
      expect(seen).to include(a_hash_including(volume_app_id: app.id, instances: 1))
      expect(seen.find { |a| a[:volume_app_id] == app.id }[:shape].disk_gb).to eq(7)
    end

    describe "I6: capacity ops mail" do
      around { |ex| orig = Rails.cache; Rails.cache = ActiveSupport::Cache::MemoryStore.new; ex.run; Rails.cache = orig }

      it "enqueues one mail for two refusals in a row, after the rolled-back transaction" do
        server.update!(vitals: { "mem_total_mb" => 1000 })
        procs = { "web" => { cpu: "1", memory_mb: "4096", count: "1" } }
        expect {
          2.times { expect(described_class.call(app: app, user: user, processes: procs).ok).to be(false) }
        }.to have_enqueued_mail(OpsMailer, :capacity_full).once
      end

      it "check_new_shape also mails (throttled)" do
        server.update!(vitals: { "mem_total_mb" => 1000 })
        shape = Resources::Shape.new(cpu: 1.0, memory_mb: 4096)
        expect {
          2.times { described_class.check_new_shape(team: app.team, server: server, shape: shape) }
        }.to have_enqueued_mail(OpsMailer, :capacity_full).once
      end
    end

    describe ".inherited_shape_for (legacy tier)" do
      it "a legacy 1024 MB / 0.5 tier web scaled 1→2 keeps its size" do
        legacy = create(:dyno_tier, memory_mb: 1024, cpu_shares: 0.5, sleeps: false)
        app.dyno_allocations.create!(process_type: "web", count: 1, dyno_tier: legacy)
        app.process_scales.create!(process_type: "web", count: 1)
        r = described_class.call(app: app, user: user, processes: described_class.processes_for_counts(app, { "web" => "2" }))
        expect(r.ok).to be(true)
        alloc = app.dyno_allocations.find_by(process_type: "web")
        expect([ alloc.cpu.to_f, alloc.memory_mb, alloc.count ]).to eq([ 0.5, 1024, 2 ])
        expect(described_class.inherited_shape_for(app, "worker").to_h).to include(cpu: 0.5, memory_mb: 1024)
      end
    end

    describe ".processes_for_counts (I3)" do
      it "keeps a shaped allocation's shape, falls back to web's, else starter; sleeping stays sleeping" do
        app.dyno_allocations.create!(process_type: "web", count: 1, cpu: 1.0, memory_mb: 2048)
        app.dyno_allocations.create!(process_type: "clock", count: 1, dyno_tier: DynoTier.find_by!(name: "free"))
        out = described_class.processes_for_counts(app, { "web" => "3", "worker" => "2", "clock" => "1" })
        expect(out["web"]).to include(cpu: 1.0, memory_mb: 2048, count: "3")
        expect(out["worker"]).to include(cpu: 1.0, memory_mb: 2048, count: "2")
        expect(out["clock"]).to include(sleeping: true, count: "1")
        bare = create(:app_record, server: server, creator: user)
        expect(described_class.processes_for_counts(bare, { "web" => 1 })["web"]).to include(cpu: 0.25, memory_mb: 512)
      end
    end
  end
end

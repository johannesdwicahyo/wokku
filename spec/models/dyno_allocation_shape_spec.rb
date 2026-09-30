require "rails_helper"

RSpec.describe DynoAllocation do
  let(:app) { create(:app_record) }

  it "is valid with a shape and no tier" do
    expect(DynoAllocation.new(app_record: app, process_type: "web", count: 1, cpu: 0.5, memory_mb: 1024)).to be_valid
  end

  it "is valid with a tier and no shape (legacy + sleeping)" do
    expect(DynoAllocation.new(app_record: app, process_type: "web", count: 1, dyno_tier: create(:dyno_tier))).to be_valid
  end

  it "needs a tier or a shape" do
    a = DynoAllocation.new(app_record: app, process_type: "web", count: 1)
    expect(a).not_to be_valid
    expect(a.errors[:base].join).to match(/tier or a shape/)
  end

  it "rejects an off-grid shape" do
    a = DynoAllocation.new(app_record: app, process_type: "web", count: 1, cpu: 0.3, memory_mb: 512)
    expect(a).not_to be_valid
    expect(a.errors[:base].join).to match(/CPU/)
  end

  describe "legacy tier change on a shaped row" do
    let(:large)    { create(:dyno_tier, memory_mb: 2048, cpu_shares: 1.0) }
    let(:sleepy)   { create(:dyno_tier, memory_mb: 256, cpu_shares: 0.15, sleeps: true) }
    # Backfilled row: shape, no tier.
    let!(:alloc)   { DynoAllocation.create!(app_record: app, process_type: "web", count: 1, cpu: 0.5, memory_mb: 512) }

    it "clears the shape so the new tier governs" do
      alloc.update!(dyno_tier: large)
      alloc.reload
      expect(alloc.shape).to be_nil
      expect([ alloc.effective_cpu, alloc.effective_memory_mb ]).to eq([ 1.0, 2048 ])
    end

    it "goes back to sleeping on a sleeping tier" do
      alloc.update!(dyno_tier: sleepy)
      expect(alloc.reload).to be_sleeping
    end

    it "keeps a shape written in the same save (builder path)" do
      alloc.update!(dyno_tier: large, cpu: 2.0, memory_mb: 4096)
      expect(alloc.reload.shape).to eq(Resources::Shape.new(cpu: 2.0, memory_mb: 4096))
    end

    it "keeps the shape when the tier doesn't change" do
      alloc.update!(count: 2)
      expect(alloc.reload.shape).to be_present
    end
  end
end

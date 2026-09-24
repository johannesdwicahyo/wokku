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
end

require "rails_helper"

RSpec.describe RestoreDrill do
  it "has a passed/failed status enum and defaults to passed" do
    expect(described_class.statuses.keys).to contain_exactly("passed", "failed")
    expect(create(:restore_drill).status).to eq("passed")
  end

  it "persists byte-sized volume counts beyond int4 range (bigint columns)" do
    drill = create(:restore_drill, restored_rows: 5_000_000_000)

    expect(drill.reload.restored_rows).to eq(5_000_000_000)
  end
end

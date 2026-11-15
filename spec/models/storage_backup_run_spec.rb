require "rails_helper"

RSpec.describe StorageBackupRun do
  let(:server) { create(:server) }

  def run!(days_ago, status: "ok", kind: "sync")
    create(:storage_backup_run, server: server, kind: kind, status: status, created_at: days_ago.days.ago)
  end

  it "green_streak counts 7 for seven daily ok syncs" do
    7.times { |i| run!(i) }
    expect(described_class.green_streak(server)).to eq(7)
  end

  it "green_streak resets after a failed day and is 0 with no runs" do
    expect(described_class.green_streak(server)).to eq(0)
    run!(0); run!(1, status: "failed"); run!(2)
    expect(described_class.green_streak(server)).to eq(1)
  end

  it "green_streak is not broken by a day with no run yet today" do
    run!(1); run!(2)
    expect(described_class.green_streak(server)).to eq(2)
  end

  it "last_drill_ok? follows the latest drill" do
    expect(described_class.last_drill_ok?(server)).to be(false)
    run!(2, kind: "drill"); run!(1, kind: "drill", status: "failed")
    expect(described_class.last_drill_ok?(server)).to be(false)
    run!(0, kind: "drill")
    expect(described_class.last_drill_ok?(server)).to be(true)
  end
end

require "rails_helper"

RSpec.describe Preview::IdleSweepJob do
  it "delegates to sweeper" do
    expect(Preview::IdleSweeper).to receive(:sweep)
    described_class.new.perform
  end
end

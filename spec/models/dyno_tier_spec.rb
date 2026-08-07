require "rails_helper"

RSpec.describe DynoTier do
  describe "#hourly_price_cents" do
    it "derives from monthly (720h)" do
      tier = DynoTier.new(name: "basic", memory_mb: 512, cpu_shares: 50, monthly_price_cents: 720, sleeps: false)
      expect(tier.hourly_price_cents).to be_within(0.0001).of(1.0)
    end
  end

  describe "#free?" do
    it "returns true when monthly_price_cents is 0" do
      tier = DynoTier.new(monthly_price_cents: 0, sleeps: true)
      expect(tier.free?).to be true
    end
  end

  describe "#size_key (canonical box vocabulary, derived from name)" do
    {
      "free" => "sleeping", "basic" => "small", "standard" => "medium",
      "performance" => "large", "performance-2x" => "xlarge"
    }.each do |tier_name, box_size|
      it "maps the #{tier_name} tier to #{box_size}" do
        tier = build(:dyno_tier, name: tier_name)
        expect(tier.size_key).to eq(box_size)
      end
    end

    it "falls back to a memory-MB bucket for an unknown tier name" do
      expect(build(:dyno_tier, name: "bespoke", memory_mb: 256).size_key).to eq("sleeping")
      expect(build(:dyno_tier, name: "bespoke", memory_mb: 1024).size_key).to eq("medium")
      expect(build(:dyno_tier, name: "bespoke", memory_mb: 4096).size_key).to eq("xlarge")
    end
  end
end

require "rails_helper"

# Seeds (including db:seed:replant in CI) pre-populate default service
# tiers like "basic/postgres". Use unique names here so these tests
# don't collide with whatever the DB has been seeded with.
RSpec.describe ServiceTier do
  it "is valid" do
    tier = ServiceTier.new(
      name: "test-tier-valid",
      service_type: "postgres",
      price_cents_per_hour: 0.7,
      spec: { storage_gb: 10, connections: 20 }
    )
    expect(tier).to be_valid
  end

  it "requires name and service_type" do
    tier = ServiceTier.new
    expect(tier).not_to be_valid
    expect(tier.errors[:name]).to include("can't be blank")
    expect(tier.errors[:service_type]).to include("can't be blank")
  end

  it "requires unique name per service_type" do
    ServiceTier.create!(name: "test-tier-dup", service_type: "postgres", price_cents_per_hour: 0.7)
    dup = ServiceTier.new(name: "test-tier-dup", service_type: "postgres", price_cents_per_hour: 0.7)
    expect(dup).not_to be_valid
  end

  it "free? returns true when price is zero" do
    tier = ServiceTier.new(price_cents_per_hour: 0)
    expect(tier.free?).to be true
  end

  it "hourly_price_cents derives from monthly" do
    tier = ServiceTier.new(monthly_price_cents: 720)
    expect(tier.hourly_price_cents).to be_within(0.0001).of(1.0)
  end

  it "daily_price_cents derives from monthly" do
    tier = ServiceTier.new(monthly_price_cents: 300)
    expect(tier.daily_price_cents).to be_within(0.0001).of(10.0)
  end

  it "exposes GFS policies per tier (founder-locked numbers)" do
    { "basic" => { daily: 7, weekly: 0, monthly: 0 },
      "standard" => { daily: 7, weekly: 4, monthly: 1 },
      "performance" => { daily: 7, weekly: 4, monthly: 3 } }.each do |name, gfs|
      tier = described_class.new(name: name)
      expect(tier.gfs_policy).to eq(gfs)
    end
  end
end

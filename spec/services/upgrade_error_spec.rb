require "rails_helper"

RSpec.describe UpgradeError do
  it "is the parent of every subclass" do
    expected = %w[
      NoSharedTenant PlanNoSlots NoFreeSlots ExceedsDedicatedCap
      ProvisioningFailed MigrationFailed CutoverFailed RollbackFailed
    ]
    expected.each do |name|
      klass = described_class.const_get(name)
      expect(klass.ancestors).to include(described_class)
    end
  end

  it "each subclass has a UI_MESSAGE constant" do
    described_class.constants.each do |c|
      klass = described_class.const_get(c)
      next unless klass.is_a?(Class) && klass.ancestors.include?(described_class) && klass != described_class
      expect(klass.const_get(:UI_MESSAGE)).to be_a(String), "#{klass} missing UI_MESSAGE"
    end
  end

  it "ExceedsDedicatedCap accepts size + cap kwargs and interpolates with engine label" do
    err = UpgradeError::ExceedsDedicatedCap.new(size_mb: 800, cap_mb: 512, plan: "Solo", next_plan: "Pro")
    expect(err.message).to eq("Your Postgres is 800 MB but Solo's dedicated cap is 512 MB. Upgrade to Pro to migrate.")

    redis = UpgradeError::ExceedsDedicatedCap.new(size_mb: 200, cap_mb: 128, plan: "Solo", next_plan: "Pro", engine: "redis")
    expect(redis.message).to eq("Your Redis is 200 MB but Solo's dedicated cap is 128 MB. Upgrade to Pro to migrate.")
  end

  it "NoFreeSlots / PlanNoSlots / NoSharedTenant interpolate the engine label" do
    expect(UpgradeError::NoFreeSlots.new.message).to include("dedicated Postgres slots")
    expect(UpgradeError::NoFreeSlots.new(engine: "redis").message).to include("dedicated Redis slots")
    expect(UpgradeError::PlanNoSlots.new(engine: "redis").message).to include("dedicated Redis")
    expect(UpgradeError::NoSharedTenant.new(engine: "redis").message).to include("shared Redis")
  end
end

require "rails_helper"

RSpec.describe Wokku::Providers do
  subject(:config) { described_class.new }
  let(:shape) { Resources::Shape.new(cpu: 0.5, memory_mb: 1024) }

  it "defaults pricing to a null that shows no prices" do
    expect(config.pricing.monthly_idr(shape)).to be_nil
    expect(config.pricing.unit_prices).to be_nil
  end

  it "defaults the resource builder ON for self-host" do
    expect(config.resource_builder?).to be(true)
  end

  it "accepts injected values" do
    pricing = Object.new
    config.pricing = pricing
    config.resource_builder = false
    expect(config.pricing).to be(pricing)
    expect(config.resource_builder?).to be(false)
  end

  it "null plan enforcer allows any resource change" do
    expect(config.plan_enforcer.allowed?(nil, :resources, from: [], to: [ { shape: shape, instances: 3 } ])).to be(true)
  end
end

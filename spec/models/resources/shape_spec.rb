require "rails_helper"

RSpec.describe Resources::Shape do
  it "accepts on-grid values" do
    expect(described_class.new(cpu: 0.5, memory_mb: 1024, disk_gb: 5)).to be_valid
  end

  it "rejects off-grid and out-of-range values" do
    [
      { cpu: 0.3,  memory_mb: 512 },
      { cpu: 0.25, memory_mb: 300 },
      { cpu: 0,    memory_mb: 512 },
      { cpu: 4.25, memory_mb: 512 },
      { cpu: 0.25, memory_mb: 8448 },
      { cpu: 0.25, memory_mb: 512, disk_gb: -1 },
      { cpu: 0.25, memory_mb: 512, disk_gb: 101 }
    ].each do |attrs|
      expect(described_class.new(**attrs)).not_to be_valid, attrs.inspect
    end
  end

  it "coerces string input (API params) before validating" do
    shape = described_class.new(cpu: "0.75", memory_mb: "768", disk_gb: "2")
    expect(shape).to be_valid
    expect(shape.to_h).to eq(cpu: 0.75, memory_mb: 768, disk_gb: 2)
  end

  it "accepts whole-number floats for memory_mb and disk_gb" do
    shape = described_class.new(cpu: 0.5, memory_mb: 1024.0, disk_gb: 5.0)
    expect(shape).to be_valid
    expect(shape.to_h).to eq(cpu: 0.5, memory_mb: 1024, disk_gb: 5)
  end

  it "accepts whole-number float strings for memory_mb and disk_gb" do
    shape = described_class.new(cpu: 0.5, memory_mb: "1024.0", disk_gb: "5.0")
    expect(shape).to be_valid
    expect(shape.to_h).to eq(cpu: 0.5, memory_mb: 1024, disk_gb: 5)
  end

  it "rejects non-whole-number floats for memory_mb and disk_gb" do
    expect(described_class.new(cpu: 0.5, memory_mb: 300.5)).not_to be_valid
    expect(described_class.new(cpu: 0.5, memory_mb: 1024, disk_gb: 5.5)).not_to be_valid
  end

  it "treats garbage strings as invalid, not zero-but-valid" do
    expect(described_class.new(cpu: "abc", memory_mb: 512)).not_to be_valid
  end

  it "round_up snaps up onto the grid and clamps" do
    expect(described_class.round_up(cpu: 0.3, memory_mb: 512).to_h).to eq(cpu: 0.5, memory_mb: 512, disk_gb: 0)
    expect(described_class.round_up(cpu: 0.15, memory_mb: 100).to_h).to eq(cpu: 0.25, memory_mb: 256, disk_gb: 0)
    expect(described_class.round_up(cpu: 9, memory_mb: 99_999, disk_gb: 1.2).to_h).to eq(cpu: 4.0, memory_mb: 8192, disk_gb: 2)
  end

  it "ships the five app presets, all on-grid" do
    expect(described_class::PRESETS.keys).to eq(%w[nano starter standard pro big])
    described_class::PRESETS.each_value { |p| expect(described_class.new(**p)).to be_valid }
  end

  it "ships on-grid service presets for every dedicated engine" do
    %w[postgres redis mariadb mongodb].each do |engine|
      described_class::SERVICE_PRESETS.fetch(engine).each_value { |p| expect(described_class.new(**p)).to be_valid }
    end
  end
end

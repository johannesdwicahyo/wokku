# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resources::Shape do
  describe "engine memory floor" do
    # 128 MB OOM-killed mongo's first-boot init before the root user existed
    # (prod smoke 2026-10-07); the builder must not offer it.
    it "rejects mongodb below 512 MB with a clear error" do
      shape = described_class.new(cpu: 0.25, memory_mb: 256, disk_gb: 5)
      expect(shape.valid?(engine: "mongodb")).to be false
      expect(shape.errors(engine: "mongodb")).to include("mongodb needs at least 512 MB memory")
    end

    it "accepts mongodb at the floor and leaves other engines (and no engine) unchanged" do
      expect(described_class.new(cpu: 0.25, memory_mb: 512, disk_gb: 5).valid?(engine: "mongodb")).to be true
      small = described_class.new(cpu: 0.25, memory_mb: 256, disk_gb: 5)
      expect(small.valid?(engine: "postgres")).to be true
      expect(small.valid?).to be true
    end
  end
end

require "rails_helper"

RSpec.describe Resources::CapacityGuard do
  let(:server) { create(:server, vitals: { "mem_total_mb" => 10_000 }) }
  let(:app)    { create(:app_record, server: server) }

  before do
    app.dyno_allocations.create!(process_type: "web", count: 1, cpu: 1.0, memory_mb: 4096)
    app.process_scales.create!(process_type: "web", count: 2)
  end

  it "sums allocation memory × instances" do
    expect(described_class.reserved_mb(server)).to eq(8192)
  end

  it "refuses a change that crosses 90% of host RAM" do
    expect { described_class.check!(server, add_mb: 1000) }.to raise_error(described_class::Full, /capacity/)
  end

  it "allows a change under 90%" do
    expect { described_class.check!(server, add_mb: 800) }.not_to raise_error
  end

  it "never blocks without telemetry or on a downsize" do
    server.update!(vitals: {})
    expect { described_class.check!(server, add_mb: 99_999) }.not_to raise_error
    server.update!(vitals: { "mem_total_mb" => 1 })
    expect { described_class.check!(server, add_mb: -512) }.not_to raise_error
  end

  describe ".check_change!" do
    let(:host) { create(:server, vitals: { "mem_total_mb" => 10_000 }) }

    it "passes when the post-change reserved total is under 90% even if the change grew it" do
      resized_app = create(:app_record, server: host)
      resized_app.dyno_allocations.create!(process_type: "web", count: 1, cpu: 1.0, memory_mb: 2048)
      resized_app.process_scales.create!(process_type: "web", count: 1)

      expect { described_class.check_change!(host, before_mb: 500) }.not_to raise_error
    end

    it "raises when the post-change total crosses 90%" do
      resized_app = create(:app_record, server: host)
      resized_app.dyno_allocations.create!(process_type: "web", count: 1, cpu: 1.0, memory_mb: 8192)
      resized_app.process_scales.create!(process_type: "web", count: 2)

      expect { described_class.check_change!(host, before_mb: 500) }.to raise_error(described_class::Full, /capacity/)
    end

    it "never raises on a shrink, even when the resulting total is still over 90%" do
      resized_app = create(:app_record, server: host)
      resized_app.dyno_allocations.create!(process_type: "web", count: 1, cpu: 1.0, memory_mb: 8192)
      resized_app.process_scales.create!(process_type: "web", count: 2)

      expect { described_class.check_change!(host, before_mb: 20_000) }.not_to raise_error
    end

    it "never raises without mem_total_mb telemetry" do
      host.update!(vitals: {})
      resized_app = create(:app_record, server: host)
      resized_app.dyno_allocations.create!(process_type: "web", count: 1, cpu: 1.0, memory_mb: 8192)
      resized_app.process_scales.create!(process_type: "web", count: 2)

      expect { described_class.check_change!(host, before_mb: 0) }.not_to raise_error
    end
  end
end

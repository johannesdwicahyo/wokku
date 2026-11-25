require "rails_helper"

RSpec.describe Apps::CpuSparks do
  let(:now) { Time.utc(2026, 11, 25, 12, 0, 0) }
  let(:a) { create(:app_record) }
  let(:b) { create(:app_record) }

  def metric(app, cpu, ago)
    Metric.create!(app_record: app, cpu_percent: cpu, recorded_at: now - ago)
  end

  it "maps per-bucket CPU (containers summed, polls averaged) oldest first; gaps are nil" do
    metric(a, 10, 1.minute)
    metric(a, 20, 1.minute) # second container, same poll -> 30
    metric(b, 7, 57.minutes)
    r = described_class.for([ a, b, create(:app_record) ], now: now)
    expect(r[a.id]).to eq(Array.new(11) + [ 30 ])
    expect(r[b.id]).to eq([ 7 ] + Array.new(11))
    expect(r.values.last).to eq(Array.new(12))
    expect(r.values.map(&:size).uniq).to eq([ 12 ])
  end

  it "uses the same number of queries for 2 and 10 apps" do
    count = lambda do |apps|
      n = 0
      cb = ->(*, payload) { n += 1 unless payload[:name] == "SCHEMA" }
      ActiveSupport::Notifications.subscribed(cb, "sql.active_record") { described_class.for(apps, now: now) }
      n
    end
    two = create_list(:app_record, 2)
    ten = create_list(:app_record, 10)
    expect(count.(ten)).to eq(count.(two))
  end
end

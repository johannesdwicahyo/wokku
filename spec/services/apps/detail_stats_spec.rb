require "rails_helper"

RSpec.describe Apps::DetailStats do
  let(:app) { create(:app_record) }
  let(:now) { Time.utc(2026, 11, 26, 10, 40) }
  let(:stats) { described_class.for(app, now: now) }

  def metric(at, cpu, mem: 100 * 1024 * 1024)
    Metric.create!(app_record: app, cpu_percent: cpu, memory_usage: mem, memory_limit: 512 * 1024 * 1024, recorded_at: at)
  end

  def bucket(at, count, p95: nil, e5: 0)
    RequestAggregate.create!(app_record: app, bucket_start: at, req_count: count, p95_ms: p95, error_5xx: e5)
  end

  it "buckets the last 24 h into 24 hourly cpu/mem values from raw metrics" do
    metric(now - 30.minutes, 40)
    metric(now - 90.minutes, 20)
    metric(now - 85.minutes, 30)
    expect(stats[:cpu].size).to eq 24
    expect(stats[:cpu].last).to eq 40.0
    expect(stats[:cpu][-2]).to eq 25.0
    expect(stats[:mem].last).to eq 100.0
    expect(stats[:mem_limit_mb]).to eq 512
    expect(stats[:cpu_now]).to eq 40.0
  end

  it "reports last_metric_at and drops stale memory for a stopped app" do
    expect(described_class.for(app, now: now)[:last_metric_at]).to be_nil
    metric(now - 3.hours, 40)
    app.update_columns(status: AppRecord.statuses[:stopped], live_mem_used_mb: 99)
    expect(described_class.for(app, now: now)[:last_metric_at]).to eq now - 3.hours
    expect(described_class.for(app, now: now)[:mem_now_mb]).to be_nil
    app.update_columns(status: AppRecord.statuses[:running])
    expect(described_class.for(app, now: now)[:mem_now_mb]).to eq 99
  end

  it "fills hours that only exist in MetricHourly" do
    MetricHourly.create!(app_record: app, hour_start: (now - 20.hours).beginning_of_hour, avg_cpu_percent: 12, sample_count: 5)
    expect(stats[:cpu][3]).to eq 12.0
    metric(now - 20.hours, 50)
    expect(described_class.for(app, now: now)[:cpu][3]).to eq 50.0
  end

  it "sums RequestAggregate per hour into requests per minute" do
    bucket(now - 10.minutes, 600)
    bucket(now - 20.minutes, 600)
    expect(stats[:req].last).to eq 20.0
    expect(stats[:rpm_now]).to eq 20.0
  end

  it "computes last-hour p95 and 5xx share" do
    bucket(now - 10.minutes, 7_000, p95: 150, e5: 1)
    bucket(now - 20.minutes, 7_920, p95: 184, e5: 2)
    expect(stats[:p95_ms]).to eq 184
    expect(stats[:req_hour]).to eq 14_920
    expect(stats[:err_5xx_hour]).to eq 3
    expect(stats[:err_5xx_pct]).to eq 0.02
  end

  it "returns nils and zeros for an app with no data" do
    expect(stats.values_at(:cpu, :mem, :req)).to all(eq(Array.new(24)))
    expect(stats.values_at(:p95_ms, :err_5xx_pct, :rpm_now, :cpu_now)).to all(be_nil)
    expect(stats[:req_hour]).to eq 0
  end

  it "uses at most 4 queries" do
    metric(now - 30.minutes, 40)
    bucket(now - 10.minutes, 600, p95: 100)
    MetricHourly.create!(app_record: app, hour_start: (now - 20.hours).beginning_of_hour, avg_cpu_percent: 12, sample_count: 5)
    n = 0
    sub = ActiveSupport::Notifications.subscribe("sql.active_record") { |*, p| n += 1 unless %w[SCHEMA TRANSACTION].include?(p[:name]) || p[:cached] }
    described_class.for(app, now: now)
    ActiveSupport::Notifications.unsubscribe(sub)
    expect(n).to be <= 4
  end
end
